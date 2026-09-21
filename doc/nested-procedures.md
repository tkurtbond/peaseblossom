# Nested procedures — plan

Status (2026-09-20): **not implemented in the LLVM backend; the front end
accepts them.** A nested procedure declaration, or a call of one, is a compile
error from the LLVM backend (`LLVMCodeGenerator.ReportNestedProcedures`, and
`Unsupported` at each call). Before that change it compiled to a comment in the
IR and a program quietly missing the call. This document is the plan for
lowering them properly. It is listed in `PLAN.md` as Phase 11 step 8.

## 1. What the language says

`Oberon2.pdf` §10: "All constants, variables, types, and procedures declared
within a procedure body are local to the procedure. Since procedures may be
declared as local objects too, procedure declarations may be nested. The call
of a procedure within its declaration implies recursive activation. Objects
declared in the environment of the procedure are also visible in those parts of
the procedure in which they are not concealed by a locally declared object with
the same name." The declaration sequence of a body ends with
`{ProcedureDeclaration ";" | ForwardDeclaration ";"}`, so forward declarations
occur among nested procedures too.

§6.5: a procedure assigned to a procedure variable "must not be a predeclared or
type-bound procedure nor may it be local to another procedure". The checker
enforces that already (`SemanticActions.Mod`, "a procedure local to another
procedure cannot be used as a procedure value"; fixture
`semantic-reject-procedure-value`). **This is what makes the design below
enough**: a nested procedure is only ever called by name, from inside the
procedure that declares it or from something nested in that, so an activation
of it never outlives the activation of its enclosing procedure. No closure
escapes.

What a nested procedure can do, and so what the implementation must support:

- read and write the enclosing procedure's locals, value and `VAR` parameters,
  receiver, `FOR` control variables, `WITH`-narrowed names (the narrowing is
  static: it sees the declared type);
- the same for every procedure that encloses that one, to any depth;
- call itself, its siblings, its ancestors' nested procedures, its own nested
  procedures, and the enclosing procedure (recursion);
- appear inside a type-bound procedure (then the receiver is one of the
  variables it can use);
- be forward-declared (`PROCEDURE ^ P;`) and completed later in the same
  declaration sequence, for mutual recursion.

Not in scope: nested procedures as procedure values (illegal), nested
procedures as type-bound procedures (the grammar does not allow it), export of
one (`.sym` files never mention a local procedure, as now).

## 2. Where things stand

| Piece | State |
|---|---|
| Parser, `SyntaxTree.ProcDeclNode.declarations.procDecls` | complete; nested lists are ordinary `ProcDeclNode` chains |
| Checker: scoping, uplevel names, calls, recursion, forward declarations, the procedure-value ban, the `WITH` safety check that already reasons about nested reassignment (`MayBeReassignedElsewhere`) | complete; fixtures `semantic-procedures`, `semantic-reject-procedure-value` |
| `SymbolTable.ScopeDesc.enclosingProc` — the `ProcDeclNode` a scope sits inside, set by `OpenProcedureBodyScope` for every procedure, nested or not | exists; already used to tell "declared directly inside procedure P" from "module-level" |
| `SemanticActions.OpenProcedureBodyScope` (used by the backend to re-open a body scope) | resolves the body's CONST/TYPE/VAR and the parameters, **not** its nested procedures: those are resolved only inside the checker's own `CheckProcedureBody`, with full diagnostics |
| Backend `cg.locals` (`LocalBinding`: object → address text, plus a hidden tag and open-array lengths) | the single place that decides where a variable lives; a designator's codegen only ever asks `FindLocalBinding(obj)` |
| Backend function symbols, `EmitProcSignature`, `BindFormalParams`, `BindLocalVars`, `BindReceiver` | top-level (`@Module.name`) and type-bound (`@Module.Type.Method`) only |
| Any lowering of a nested procedure | none |

The `cg.locals` row is the key to the design: **the backend resolves every
variable through one table**. If a nested procedure's body finds
an enclosing procedure's variable in that table with an address that is valid
inside the nested function, no other code has to change.

## 3. Design: lambda lifting by reference

Lift each nested procedure to an ordinary LLVM function, and pass it the
*addresses* of the enclosing variables it uses as extra hidden parameters.

- `PROCEDURE Outer; VAR n: INTEGER; PROCEDURE Add(k: INTEGER); BEGIN n := n + k END Add; BEGIN Add(3) END Outer`
  becomes `define @M.Outer.Add(i16 %k, ptr %n.addr)` and the call
  `call @M.Outer.Add(i16 3, ptr %n)` where `%n` is `Outer`'s own alloca.
- In `Add`, `BindLocal(cg, nObj, "%n.addr")`: the object `n` now has a binding
  whose address is the hidden parameter. Every load, store, `SYSTEM.ADR`,
  `WITH`, `FOR` and `COPY` that names `n` works without change.
- A variable that is itself a `VAR` parameter of `Outer` already has a binding
  whose address is the pointer it was passed; that pointer is what is passed on.
- Only what a nested procedure *needs* is passed (below), not a whole frame.

Why this is a complete implementation of static scoping here: an access to an
enclosing variable must reach the frame of the *lexically enclosing activation*,
not just any activation of that procedure. Passing the caller's own view of each
variable does that: a call from the enclosing procedure passes its own locals; a
call from a sibling or a child passes what that caller was itself passed for the
same object; a recursive call of the enclosing procedure creates a new activation
with its own locals, and calls made from it pass those. Since no nested
procedure escapes (§1), no activation is ever reached after it has returned.

### 3.1 Which variables a nested procedure needs

`Needs(N)`, an ordered list of `SymbolTable.Object`s, for each nested procedure
`N`:

    Needs(N) = Direct(N)
             ∪ ⋃ over each procedure Q nested inside N:        Needs(Q) \ Declared(N)
             ∪ ⋃ over each nested procedure M that N calls:    Needs(M) \ Declared(N)

- `Direct(N)`: the variables declared in a procedure that *strictly encloses* N
  (a local, a value or `VAR` parameter, the receiver) that N's own body names.
  Module-level variables are not free (they are addressed by symbol), nor are
  constants and types (no run-time storage), nor N's own locals and those of
  anything nested inside it.
- The second term: N must be able to hand on what a procedure nested in it
  needs, even if N never names that variable itself (a level-3 procedure reading
  a level-1 local through a level-2 procedure that does not mention it).
- The third term: a call needs the callee's variables to be in hand. `M` ranges
  over the nested procedures visible to `N`: itself, siblings, the enclosing
  procedure's other nested procedures, `N`'s own children, and the nested
  procedures of every ancestor. Calls of the enclosing top-level procedure need
  nothing (it is an ordinary function) unless it is itself nested.
- `\ Declared(N)`: what `N` declares itself does not have to be passed *to* it.

The terms are mutually dependent (recursion, mutual recursion), so this is a
fixed point over a small graph: iterate until no `Needs` set grows. The sets only
grow and are bounded by the variables in scope, so it terminates.

**Determinism.** The order of each list decides the order of hidden parameters
and so the emitted IR, and `make stage2` compares that byte for byte. Order by
declaring procedure from outermost to innermost, then by declaration order within
it (`declLine`, `declColumn`). Never by pointer or by discovery order.

**Exact, not by name (decided 2026-09-20).** `MayBeReassignedElsewhere` gets by with matching bare
names (an over-approximation is safe for a check that only rejects). Here an
over-approximation costs a hidden parameter that is never used, and a *wrong*
match (a same-named variable in an unrelated scope) is a correctness bug in the
other direction if it pairs an object with a binding that does not exist. Resolve
each base identifier against the nested procedure's real scope chain
(`SymbolTable.Find`) and take the object that comes back.

What "names a variable" covers, for the walk: the base identifier of every
designator, in every statement and expression form. `LLVMCodeGenerator.
CollectStringConstants` already walks every statement and expression node and is
the model for completeness; the new walker mirrors its cases one to one. That
includes the arguments of predeclared procedures (`INC(x)`, `NEW(p)`, `COPY(a,b)`,
`LEN(x)`), the variables of `FOR`, `WITH` and `CASE`, `SYSTEM.ADR(x)`, and the
callee name of every call (a call target is what puts `M` in the third term).

### 3.2 What a hidden parameter looks like

Per needed object, in `Needs` order, appended after the ordinary parameters:

| the variable is | hidden parameters |
|---|---|
| a local, value parameter, `FOR` variable, or any scalar/record/array | `ptr` (its address) |
| a `VAR` parameter of record type, or a receiver that is one | `ptr` (its address), then `ptr` (its run-time type tag: `LocalBinding.tagText`, `NeedsHiddenTag`) |
| an open-array parameter (value or `VAR`) | `ptr` (its address), then one word-sized length per open dimension (`LocalBinding.dope`) |
| a pointer variable | `ptr` (its address); the pointer value lives where it always did |

All of these are read from the *caller's* `LocalBinding` for the object, which
exists whether the caller owns the variable or received it as a hidden parameter
itself. The nested function binds them under the same object with `BindLocal`,
`BindLocalWithTag` or `BindLocalWithDope`, exactly as `BindFormalParams` does for
ordinary parameters.

Nested procedures are never procedure values, so no calling-convention
constraint applies to the hidden parameters and they can go last. Calls are
always direct.

Because every access to a variable is a load or store through its address (the
generator emits `alloca` plus loads and stores and leaves promotion to LLVM), no
value is cached in a register across a call that could change it. The address
escaping into the callee is what tells LLVM's optimizer, if it runs at all, that
it may.

### 3.3 The garbage collector

The collector scans the stack conservatively (`GarbageCollectedHeap`). A pointer
variable of an enclosing procedure stays in that procedure's frame, on the stack,
and the nested procedure reaches it through an address into that frame. Nothing
moves and nothing new is hidden from the scan. A fixture must still prove it
(§6), because "nothing changes" is the kind of claim this project has been wrong
about.

### 3.4 Symbols

`@Module.Outer.Inner`, nested arbitrarily: the chain of names from the
module-level procedure inward. For a nested procedure inside a type-bound one,
`@Module.Type.Method.Inner` (`MethodSymbol` plus `.Inner`). Identifiers cannot
contain a dot, so there is no collision with a module-level name. Two outer
procedures may each have a nested `Helper`. The VAX backend's 31-character limit
is Phase 13's problem, as for every other name.

### 3.5 Emission order

The IR is written to one `Files.Rider` in order, so a nested function cannot be
generated in the middle of its enclosing one. Emit every nested function *before*
the enclosing function's `define`; LLVM does not care about the order of
functions in a module. `GenerateProcedureBody` for a module-level (or
type-bound) procedure therefore does, in this order: open its body scope; declare
and analyze its nested procedures (§4); emit each nested function, children
before parents or in any fixed order; then its own signature and body as today.
Nothing is interleaved, so the per-function state (`cg.locals`, `cg.scope`,
`cg.currentProcResultType`, the loop-exit label, `cg.narrowings`) is saved and
restored around each function as it already is between two top-level functions.
Temporaries and labels are numbered per program (`cg.nextTemp`), not per
function, so no renumbering.

## 4. The pieces

**`SemanticActions` (front end, small).** Export a silent
`DeclareLocalProcedures(pd, bodyScope)`: for each body declaration in `pd`'s
`procDecls`, in order, resolve its signature, insert (or find, if a forward
declaration put it there) its `procClass` object in `bodyScope`, and return.
No body checking, no diagnostics: the source has already passed
`CheckModule` with none, the same premise `OpenProcedureBodyScope`'s own comment
states. (`ResolveProcDecls` does this and also checks bodies, which is
duplicated work and the wrong place to grow flags.) `OpenProcedureBodyScope`
already opens a nested procedure's own scope given its parent's.

**A new backend-independent module, `NestedProcedures.Mod` (`src/front/`).**
Given a top-level procedure's declaration and body scope it builds the tree of
its nested procedures and computes `Needs`. It imports `SemanticActions`,
`SymbolTable`, `Types`, `SyntaxTree`; nothing from `src/back`. Per nested
procedure it records: the declaration, its `procClass` object, its
`ProcedureType`, the body scope it opened, its parent, its children, its
declaring depth, and `needs`. The scope objects it creates are the ones the
backend must then use (bindings are keyed by object identity, and re-opening a
scope makes fresh objects, per the comment on `OpenProcedureBodyScope`), so the
backend takes them from here and never re-opens.

The module is backend-independent on purpose: the VAX backend (§8) needs the same
sets. It is written in strict Oberon-2 with no nested procedures of its own, as
poc's own source must be until it can compile them.

**`poc -dump-nested <file>` (a debugging and test mode, like `-dump-layout`).**
Prints, for every procedure that has nested ones, each nested procedure with its
`Needs` list. This is what lets the analysis be tested and golden-checked before
any codegen exists (§5, step 1) and independently of it afterwards.

**`LLVMCodeGenerator` (backend).**

- `GenerateProcedureBody` takes the body scope it is given rather than opening
  one, and (for a module-level or type-bound procedure) runs §3.5's sequence.
- A `NestedFunction` emission that mirrors `GenerateProcedureBody`: signature
  with hidden parameters appended (`EmitProcSignature` learns to append them),
  `BindFormalParams`, `BindReceiver` if inside a method, then one `BindLocal*`
  per needed object from the hidden parameters, then `BindLocalVars`, the body.
- `GenerateCall` finds a nested procedure's object, looks its `NestedProc` up,
  and emits the call with its hidden arguments taken from the caller's bindings
  (a new `GenerateNestedCall`, sharing `GenerateCallArgList` for the ordinary
  arguments). It returns the result exactly as `GenerateOrdinaryCall` does.
- Delete `ReportNestedProcedures` and the "a nested one?" message once every
  fixture passes; a nested procedure no longer routes to `Unsupported`.

## 5. Steps

Each step lands its own fixtures, which fail before it, and leaves
`make check` green (both compilers, both size models where the fixture takes
them, the fixed point). A step is not done on Linux alone: run the suite on both
BSD hosts before step 6.

0. **Groundwork, no behaviour change.** `SemanticActions.DeclareLocalProcedures`;
   `GenerateProcedureBody` takes its scope as a parameter. Proof: `make check`
   is byte-identical (same IR for every existing fixture).
   **Done 2026-09-20.** `DeclareLocalProcedures` is in `SemanticActions.Mod` (no
   caller yet: step 1 is the first, and its test); `GenerateProcedureBody` now
   takes `bodyScope`, and its two callers (`GenerateProcedureDecl`,
   `GenerateMethodDecl`) open it. Proof: every fixture source, at the default
   model, `-OC` and `-target i686-unknown-linux-gnu` (807 compilations), gives
   the same `.ll`, `.sym` and messages before and after; `make check` green,
   fixed point exact.
1. **The analysis alone.** `NestedProcedures.Mod` and `-dump-nested`. Fixtures
   `nested-analysis-*`: golden `Needs` lists for the cases in §6, including the
   ones that are easy to get wrong (a level-3 use routed through a level-2
   procedure that never names it; a sibling call that pulls a variable in; mutual
   recursion; a shadowed name that must *not* be needed; a module-level variable
   and a constant that must not be). No codegen.
   **Done 2026-09-20**: fixtures `nested-analysis-basic`, `-recursion`, `-order`,
   `-scopes`, `-kinds` and `-none`. `-kinds` has one nested procedure for each
   statement and expression form that can name a variable, and the receivers of a
   pointer and of a `VAR` type-bound procedure. Stage 0 builds the module before
   `Poc`, which imports it for `-dump-nested`. `-dump-nested` over every source
   file of `src/` and `rtl/llvm` prints nothing, since none has a nested procedure.
2. **Nested procedures with no needs.** Emit the functions and calls for the ones
   whose `Needs` is empty; everything else stays the error. Fixture
   `llvm-nested-basic`. This exercises symbols, emission order, the
   function-versus-proper-procedure return, and calls in expressions.
   **Done 2026-09-20.** `GenerateProcedureBody` runs `NestedProcedures.Analyze`,
   generates a function for every nested procedure (`GenerateFunction`, the old
   body of `GenerateProcedureBody`) in the tree's order before the enclosing
   one's own, and leaves out - with an error at the declaration and one at each
   call - any whose `needs` is not empty. The symbol is `@Module.Outer.Inner`
   (`NestedProcedures`' `pathName`; `Type.Method.Inner` for one inside a
   type-bound procedure). A call of a nested procedure is found by its Object in
   `cg.nestedRoot`, and the string literals of nested bodies are collected too.
   `ReportNestedProcedures` and its message are gone; the replacement message
   names the remaining limit. `Analyze` returns at once for a procedure with no
   nested one, and IR for every fixture without nested procedures is unchanged
   (825 compilations, three settings). Fixtures: `llvm-nested-basic` (15 checks,
   also built with `-OC`) and `llvm-nested-features` (`NEW` and the collector,
   `WITH`, `IS`, a type-bound call, a local `TYPE`, `CASE`, string comparison, a
   `VAR` record parameter, a procedure value, all inside nested functions), both
   also run as real i686 executables; `llvm-reject-nested-procedure` checked
   what was still rejected then (a nested procedure using an enclosing variable,
   and its call) until step 3 lowered that too.
3. **Hidden parameters for scalars and aggregates.** Read and write of enclosing
   locals and value parameters, in every context (`:=`, `INC`, `FOR`, `CASE`,
   `SYSTEM.ADR`, `COPY`, `NEW`). Fixture `llvm-nested-uplevel`.
   **Done 2026-09-20**, together with steps 4 and 5: the mechanism is one for all
   kinds of variable, so there was nothing to stage. A nested function takes its
   `needs` as trailing hidden parameters, `%up.<k>` (the address), `%up.<k>.tag`
   (for a `VAR` record parameter or a `VAR` receiver) and `%up.<k>.len<d>` (an
   open array's lengths), after its own parameters, and `BindNeeds` binds them
   under the very `SymbolTable.Object` the enclosing procedure's own binding
   uses, so the body's accesses are the ordinary loads and stores through an
   address. A call passes its own binding's address, tag and lengths
   (`AppendHiddenArguments`), whether it is made by the enclosing procedure or by
   another nested one that has the variable as a hidden parameter itself.
   Fixture `llvm-nested-uplevel` (23 checks, built under `-O2` and `-OC` and the
   outputs compared) covers `INTEGER`, `REAL`, `BOOLEAN`, `SET`, `CHAR`, a
   record, an array, a pointer and `NEW` through it, `COPY` of a string, a `FOR`
   variable, a value parameter, `CASE`, `SYSTEM.ADR`, an enclosing variable
   passed on as a `VAR` argument, and shadowing.
4. **The awkward variable kinds.** `VAR` parameters, `VAR` record parameters
   (tag), open-array parameters (dope, indexing, passing on as an argument),
   the receiver of a type-bound procedure, a `WITH`-narrowed variable used from a
   nested procedure. Fixture `llvm-nested-params`.
   **Done 2026-09-20** (see step 3). `llvm-nested-params` has 11 checks: a `VAR`
   `INTEGER`; a `VAR` record parameter tested with `IS`, narrowed by `WITH`, and
   passed on as a `VAR` argument from the nested procedure (so its tag really
   travels); a `VAR` and a value open array (`LEN`, indexing, passing on; the
   value copy stays the callee's own); a two-dimensional one; a `VAR` receiver
   and a pointer receiver that the nested procedure assigns; a `WITH` over an
   enclosing pointer, `-OC` compared with `-O2`.
5. **Depth and recursion.** Three levels; a variable reached through a level that
   never names it; siblings calling each other; mutual recursion through a forward
   declaration; a nested procedure calling its enclosing one; deep recursion
   (each activation with its own locals). Fixture `llvm-nested-deep`.
   **Done 2026-09-20** (see step 3). `llvm-nested-deep` (8 checks): three and four
   levels, a sibling relay that reaches a variable only through two procedures
   that never name it, mutual recursion through `PROCEDURE ^`, a nested procedure
   calling its enclosing one and a recursive enclosing one, and two unrelated
   procedures with a nested procedure of the same name. Also written for this
   step: `llvm-nested-gc` (an enclosing local, `VAR` parameter, record field and
   array element that only a frame holds, across collections started by nested
   procedures), `llvm-nested-import` (`Tally.mod`'s exported procedures, one
   type-bound, use nested ones; the `.sym` has none of them) and `llvm-nested-ir`
   (golden IR, both word sizes, `clang` accepts both). All the runtime ones are
   in `llvm-i686-runtime`.
   One thing the tests found: an open array parameter of more than 8
   dimensions - which the length vector cannot hold - crashed `poc` itself with a
   run-time index error (unrelated to nested procedures, the code is older), and
   `NEW` of such a pointer was quietly accepted. An open array type with more than
   `Types.maxOpenDimensions` (8) open dimensions is now an error where the checker
   resolves it (fixture `semantic-reject-open-array-dimensions`); fixed dimensions
   are not limited. `llvm-reject-nested-procedure` became
   `llvm-reject-external-vms` (the same "nothing written" checks, with an external
   `["VMS"]` procedure, which the LLVM backend used to lower as a C call and now
   reports), and `poc-exit-status`'s unsupported-program case moved to it too.
6. **Close.** The error and its message are already gone (step 3) and
   `llvm-reject-nested-procedure` is now `llvm-reject-external-vms` (its
   program, printing `ok`, is in `llvm-nested-uplevel`); left: `AGENTS.md` gets "Nested procedures (implemented)" with
   what a program can observe; `PLAN.md`, `000-todo.org`; the suite on both BSD
   hosts and at both word sizes; the fixed point re-run. Exit gate below.

## 6. Fixtures

- `nested-analysis-*` (step 1; no run): the `-dump-nested` goldens above.
- `llvm-nested-basic`: nested procedures using only globals, parameters and
  locals of their own; two levels; the same nested name under two enclosing
  procedures; a nested function called in an expression, in a `WHILE` condition
  and as an argument.
- `llvm-nested-uplevel`: read and write of an enclosing `INTEGER`, `REAL`,
  `BOOLEAN`, `SET`, `CHAR`, a record field, an array element, a pointer and what
  it points at, a string (`ARRAY OF CHAR`) filled by `COPY`; an enclosing `FOR`
  variable read inside; the enclosing variable read *after* the call to see the
  write.
- `llvm-nested-params`: as §4's step 4 list.
- `llvm-nested-deep`: as step 5.
- `llvm-nested-gc`: an enclosing pointer local is the only reference to a
  heap block while a nested procedure allocates enough to force a collection;
  the block must survive and read back intact.
- `llvm-nested-import`: a module whose *exported* procedure has a nested one,
  used from a client that sees only the `.sym`; the `.sym` must not mention the
  nested procedure.
- `llvm-nested-ir`: golden IR of a small program at both word sizes, each also
  handed to `clang`, so a change to the hidden-parameter layout is a visible
  diff.
- The runtime fixtures above run under `-O2` and `-OC` as
  `llvm-system-fixed-width` does, and are added to `llvm-i686-runtime`'s list.

## 7. Risks and open questions

- **`OpenProcedureBodyScope` makes fresh objects on every call.** Analysis and
  emission must share one set of scopes. The plan handles it (the module returns
  the scopes; the backend never re-opens) but it is the easiest thing to get
  wrong, and a wrong pairing is silent: an object with no binding resolves to a
  *module-level* symbol that does not exist, which fails at link time, so it is
  loud at least.
- **A forward-declared nested procedure.** Its object is inserted by the
  declaration and reused by the body; the analysis must treat the two as one.
- **A very long hidden parameter list (accepted 2026-09-20, until measured).**
  Legal in LLVM and on every target here;
  i386 passes them on the stack. If measurements ever show a problem, the
  fallback is one hidden pointer to a frame record holding the addresses (a static
  link), which changes only `Needs`' use in §3.2, not the analysis.
- **Type-bound procedures containing nested ones** need the receiver in
  `Needs` and `BindReceiver`'s tag; step 4 covers it, but the `MethodSymbol`
  naming for the nested function is new.
- **`WITH` inside a nested procedure narrowing an enclosing variable**: the
  narrowing list (`cg.narrowings`) is keyed by object like the bindings, so it
  should just work; step 4 tests it rather than assuming.
- **The checker's own `nonLocalAssigns`** already treats a nested procedure's
  assignment to an enclosing variable as reaching it, and rejects a `WITH` on a
  variable that could be reassigned that way (`MayBeReassignedElsewhere`). That is
  unchanged by this work.
- **Cost.** One more pass over each procedure that has nested ones, and none for
  those that do not (the analysis starts from `procDecls` and returns at once if
  it is empty). poc's own source has no nested procedures, so the fixed point is
  the check that it costs nothing there.

## 8. Alternatives considered

- **A frame record and one static-link parameter.** Allocate, for each enclosing
  procedure that has nested ones, a struct holding its captured variables, and
  pass a pointer to it. Fewer hidden parameters per call, but every captured
  variable must live *in* the struct instead of in its own `alloca`, which changes
  `BindLocalVars`, `BindFormalParams`, the address of every captured variable,
  and where a `VAR` parameter lives (it is a pointer already, so the struct would
  hold a pointer to a pointer). That touches the whole variable-storage path for a
  benefit nobody has measured. Lambda lifting by reference changes none of it.
  Kept as the fallback in §7.
- **Inline each nested procedure at its call sites.** Wrong for recursion and for
  a procedure called from many places (code size), and it still needs the
  variable mapping.
- **Keep the error and rewrite the few users.** Poc's own source has none, and
  this is legal Oberon-2 that other programs will use; the point of the compiler
  is to compile them.
- **Name-based free-variable analysis**, as `MayBeReassignedElsewhere` does:
  rejected in §3.1.

## 9. The VAX/VMS backend (Phase 13)

The mechanism there is that backend's to choose, from the VMS 5.5-2 manuals
(`AGENTS.md` names the release rule); nothing in this plan presumes one. What it
will need is the same information whichever it picks - a static link or a display
needs to know which enclosing procedures a nested one reaches, and passing
addresses needs to know which variables - and `NestedProcedures.Mod`'s output has
both. That is why the analysis lives in `src/front/` and knows nothing about LLVM.

## 10. Definition of done

- Every fixture in §6 passes under the voc-built and the poc-built `poc`, under
  `-O2` and `-OC`, at both word sizes, on Linux, NetBSD amd64 and OpenBSD i386.
- `make check`: the fixed point still exact.
- The program that `llvm-reject-nested-procedure` used to reject (now in
  `llvm-nested-uplevel`) prints `ok`. (Met, step 3.)
- No `ReportNestedProcedures`, and no "nested" message left in the backend.
- `AGENTS.md` documents nested procedures as implemented, including the two
  observable limits that remain by design: a nested procedure is not a value, and
  it is not exported.
