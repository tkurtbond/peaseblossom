# PLAN.md — Peaseblossom (poc) Development Roadmap

## Context

Peaseblossom is a from-scratch Oberon-2 compiler (`poc`) with two eventual
targets: an LLVM backend (32/64-bit) and a bespoke backend for VAX/VMS
5.5-2. The repository currently has only `README.md`, `AGENTS.md`,
`LICENSE`, and `.gitignore` — no compiler source exists yet. This plan
turns that into a concrete, phased build order so work can proceed
incrementally with a clear test story at every step, rather than
attempting the whole front end and both backends at once.

The plan is grounded in:
- `Oberon2.pdf` as the authoritative language spec (see `AGENTS.md` for why
  it supersedes `Oberon2-Report.pdf`).
- Vishap Oberon (`voc`), used two ways: as the **bootstrap compiler**
  (poc's own Oberon-2 source has to be compiled by *something* before poc
  exists) and as an **architectural reference / testing oracle** (its
  pipeline shape and test-harness style are good templates, without reusing
  its code or its terse naming).
- Four sequencing/architecture decisions already made (below), plus three
  follow-up decisions made while reviewing this plan (also below).

### Decisions locked in

| Decision | Choice |
|---|---|
| Implementation language for `poc` | **Oberon-2, self-hosted** — bootstrapped via `voc` until poc can compile itself |
| LLVM integration | Emit textual LLVM IR (`.ll`), shell out to `llc`/`clang` — no LLVM API bindings |
| VAX/VMS backend | Emit MACRO-32 assembly text only; assembling/linking/running (e.g. via SIMH + VMS 5.5-2) is **out of scope**, deferred to later, undated work |
| Backend sequencing | Shared front end first → LLVM backend to full parity → VAX/VMS backend |
| GC strategy | Bespoke mark-sweep collector (mirrors voc's approach; reuses the type descriptors already needed for `IS`/dispatch; no external C dependency) |
| Minimal stdlib for first runnable milestone | A minimal `Console`-style print-a-string module first; fuller Oakwood-style `Out`/`In` added later as fixtures need formatted output |
| Module interface mechanism | Textual, DEFINITION-like format (Appendix D4 style) — reuses the Lexer/Parser, is diffable in golden-file tests, yields a `showdef`-equivalent for free |
| LLVM-backend portability targets | Linux, NetBSD, OpenBSD, FreeBSD — a stated goal, not just 32/64-bit word size; the `rtl/llvm` platform layer must not assume Linux-only behavior |

### Naming convention

Use descriptive Oberon-2 identifiers throughout poc's own source —
**not** voc's terse module-name style (`OPS`, `OPP`, `OPT`, `OPB`, `OPV`,
`OPC`, `OPM`). Every module name below spells out its role
(`Lexer.Mod`, `SemanticActions.Mod`, `LLVMCodeGenerator.Mod`, …), and the
same applies to procedure/variable names within them.

### Bootstrap terminology

- **Stage 0**: `voc` compiles poc's own source into a working `poc`
  binary. This is load-bearing infrastructure through Phase 9, not just a
  reference — until Stage 1 exists, there is no other way to build poc.
- **Stage 1**: the Stage-0-built `poc` compiles poc's own source again.
- **Stage 2**: Stage-1's `poc` compiles poc's own source a third time.
  Stage 1 and Stage 2 output should match (modulo embedded
  timestamps/paths) — the classic self-hosting fixed-point proof.
- **Constraint**: until Stage 1 is reached, poc's own source must use only
  strict `Oberon2.pdf` syntax/semantics — none of voc's extensions
  (`-` read-only value params, `HUGEINT`, `SYSTEM.ADDRESS`/`INT8..64`/
  `SET32/64`). Otherwise Stage 1 could never recompile poc's own source
  until poc *also* implemented those same extensions. (Peaseblossom later
  adopted `HUGEINT` itself as a *target*-language extension — see
  AGENTS.md, "Language extensions beyond Oberon2.pdf" — implemented as
  ordinary Oberon-2 code in `Types.Mod` that registers the identifier;
  poc's own source never declares a variable of type `HUGEINT`, so this
  constraint still holds.)

## Directory layout

```
src/
  front/
    Lexer.Mod              -- §3 vocabulary: tokens, numbers, strings, char consts, nested comments
    Diagnostics.Mod        -- error/warning reporting, source positions
    CompilerOptions.Mod    -- option bitset, target selection (voc-style before/after-filename flag semantics);
                              unlike voc, must support an output-directory flag so build artifacts
                              (objects, executables) can be written somewhere other than the cwd
    SyntaxTree.Mod         -- AST node representation
    SymbolTable.Mod        -- Object/Type/Scope model; Insert/Find/OpenScope/CloseScope
    Types.Mod              -- type representations + Appendix A predicates (see Phase 6)
    ConstantEvaluator.Mod  -- compile-time constant folding (§5, array lengths, CASE labels, SET literals)
    Parser.Mod             -- recursive-descent grammar (Appendix B)
    SemanticActions.Mod    -- parser-driven tree construction + incremental type-checking
    PredeclaredProcedures.Mod -- semantic (arity/type) rules for ABS..NEW (§10.3); lowering lives in backends
    MemoryLayout.Mod       -- size/alignment/offset pass, target-word-size abstraction
    ModuleInterface.Mod    -- textual DEFINITION-style module interface read/write (Phase 7)
  back/
    llvm/
      LLVMTypes.Mod          -- Oberon type -> LLVM type + type-descriptor/ProcTab/BaseTypes layout (App. D5)
      LLVMCodeGenerator.Mod  -- tree walk -> textual .ll
      LLVMToolchainDriver.Mod -- shells to llc/clang, 32-bit/64-bit target triples
    vax/
      VaxTypes.Mod           -- VAX word-size/alignment/descriptor layout (hand-designed, no LLVM analogue)
      VaxCodeGenerator.Mod   -- textual MACRO-32 emission
      VaxToolchainDriver.Mod -- stub only; no assemble/link/run (Phase 10)
  driver/
    Poc.Mod                -- main program; CLI parsing (`poc options {files {options}}`, voc-style)
rtl/
  llvm/
    GarbageCollectedHeap.Mod -- bespoke mark-sweep GC
    ModuleTable.Mod          -- loaded-module/root registry
    Console.Mod              -- minimal print-a-string I/O (first milestone)
    Out.Mod, In.Mod          -- fuller Oakwood-style I/O (added later)
  vax/                        -- deferred stubs only
test/
  conformance/<feature>/{*.mod, test.sh, expected}
  testenv.sh, testresult.sh  -- voc-inspired golden-file harness, generalized over backend
tools/
  bootstrap/                 -- stage0/stage1/stage2 build scripts
```

## Phase-to-report-section map

| Phase | Report scope | New modules | Backend | Bootstrap |
|---|---|---|---|---|
| 0 | — (scaffolding) | `tools/bootstrap`, test harness | none | voc |
| 1 | §3 Vocabulary | `Lexer`, `Diagnostics` | none | voc |
| 2 | Appendix B skeleton | `SyntaxTree`, `Parser`, `SemanticActions` (stub) | none | voc |
| 3 | §4, §5, §6.1 | `SymbolTable`, `Types` (basic), `ConstantEvaluator` | none | voc |
| 4 | §6.2–§6.5 | `Types` (composite), `MemoryLayout` | none | voc |
| 5 | §7, §8, §9 (minus WITH/dispatch) | `SemanticActions` (expr/stmt) | none | voc |
| 6 | §10, WITH, Appendix A | `PredeclaredProcedures`, `SemanticActions` (procs) | none | voc — front end feature-complete |
| 7 | §11, Appendix D4 | `ModuleInterface` | none | voc |
| 8 | LLVM vertical slice | `LLVMTypes`, `LLVMCodeGenerator`, `LLVMToolchainDriver`, `rtl/llvm` (minimal) | LLVM | voc |
| 9 | LLVM full parity | GC, dispatch, open arrays, full `rtl/llvm` | LLVM | voc → **Stage 1/2 bootstrap** |
| 10 | Appendix C (optional) + MACRO-32 | `VaxTypes`, `VaxCodeGenerator`, `VaxToolchainDriver` (stub) | VAX (scoped, unverified) | poc (self-hosted) |

## Phase details

### Phase 0 — Scaffolding & bootstrap harness
Set up `src/`, `test/`, `tools/bootstrap/`. Write the golden-file harness
(`testenv.sh`/`testresult.sh`), generalized from voc's `diff -b expected
result` pattern but parameterized over a backend variable so the same
`test.sh` can later run against LLVM and (informally) VAX. First test:
compile a "hello" fixture with `voc` directly to validate the harness
plumbing before any poc code exists.

### Phase 1 — Lexer & Vocabulary (§3)
`Lexer.Mod` + `Diagnostics.Mod`; `Poc.Mod` gains a `-dump-tokens` mode.
Covers identifiers, integer/real/hex numerals, strings, char constants,
and **nesting** comments (comments containing comments — a real wrinkle
worth dedicated fixtures).
**Testing**: token-stream golden files for canonical §3 snippets; negative
fixtures for malformed nested comments/unterminated strings, cross-checked
against voc's error behavior on the same inputs.

### Phase 2 — Grammar skeleton (Appendix B), syntax only
`SyntaxTree.Mod`, `Parser.Mod`, `SemanticActions.Mod` (stub — builds an
untyped tree, no checking). `Poc.Mod` gains `-check-syntax`.
**Testing**: syntax accept/reject suite — every report example from §4–§11
must parse; deliberately mutated/broken variants must be rejected. First
point where poc can be pointed at its own Phase-1/2 source as a syntax
robustness smoke test (not a correctness check).

### Phase 3 — Declarations, scope, basic types (§4, §5, §6.1)
`SymbolTable.Mod` (Object/Type/Scope, Insert/Find/Open/CloseScope),
`Types.Mod` seeded with the numeric-type inclusion hierarchy
(`LONGREAL⊇REAL⊇LONGINT⊇INTEGER⊇SHORTINT`), `ConstantEvaluator.Mod`.
`SemanticActions.Mod` starts populating scopes, resolving qualidents,
enforcing export marks `*`/`-`, and forward `POINTER` declarations.
**Testing**: ASSERT-based fixtures per basic type and per scoping rule.
Cross-module export-visibility tests are explicitly **deferred to Phase
7** (need `ModuleInterface.Mod` first) — don't fake multi-module linking
before then.

### Phase 4 — Composite types (§6.2–§6.5)
Extend `Types.Mod` with array compatibility, record extension/base-type,
pointer-to-NIL default init, procedure-type equality via matching formal
parameter lists. Introduce `MemoryLayout.Mod` now (not deferred to
codegen) — `SIZE()`, open-array dope-vector bookkeeping, and record-offset
diagnostics all need real sizes even in a codegen-free front end, and this
forces 32-bit/64-bit width-handling discipline into the type model from
day one (voc's `History.md` explicitly warns about retrofitting this).
**Testing**: the report's own `Node`/`CenterNode`/`Tree` example family as
fixtures; ASSERT computed sizes/offsets against hand-derived values for
both a 32-bit and a 64-bit target model.

### Phase 5 — Variables, expressions, statements (§7, §8, §9 minus dispatch/WITH)
`SemanticActions.Mod` grows to implement the Appendix A
**expression-compatible operator table** as an explicit table-driven
function (a direct port of the table on p.21 of `Oberon2.pdf`, not ad hoc
per-operator code), assignment-compatibility, designators including type
guards `v(T)`, and IF/CASE/WHILE/REPEAT/FOR/LOOP+EXIT/RETURN. WITH's
type-test-and-guard form is held back to Phase 6 since it shares machinery
with type-bound-procedure dispatch.
**Testing**: the largest fixture set, drawing on the report's inline
examples throughout §8–§9 wrapped in ASSERT.
**Milestone**: `poc -check` should type-check almost any single-module
Oberon-2 program.

### Phase 6 — Procedures, type-bound procedures, predeclared procedures, WITH (§10)
Parameter matching per Appendix A — note `Oberon2.pdf`'s stricter
"identical" wording (vs. the older report's "must match") for
forward-declaration/redefinition parameter lists, flagged in `AGENTS.md`;
enforce "identical," not just "compatible". `PredeclaredProcedures.Mod`
implements arity/type rules for the full §10.3 set — semantic checking
only, lowering deferred to the backend. Type-bound procedures: receivers,
override checking, `r.P^` base-dispatch syntax.
**Testing**: the report's `Tree`/`CenterTree`/`Node` family end-to-end;
negative tests for mismatched override parameter lists.
**Exit gate**: a checklist pass against every Appendix A definition (same
type, equal types, type inclusion, type extension, assignment compatible,
array compatible, expression compatible, matching formal parameter lists)
confirming each has a corresponding function in `Types.Mod`/
`SemanticActions.Mod` and at least one positive/negative fixture.

**External procedure declarations (FFI)**: this is also the natural home
for a language extension not in `Oberon2.pdf` — declaring a procedure
heading as implemented externally (e.g. in C), needed for both the
Linux/BSD C-interop case and the eventual VAX/VMS Calling Standard case
(see `AGENTS.md`, "External procedures"). Surface syntax is decided: a
bracketed string-list attribute right after `PROCEDURE`, body-less —
`PROCEDURE ["C"] Name*(...): T;`, or `PROCEDURE ["C", "malloc"]
AllocateBytes*(...): T;` to override the linkage name — following
Component Pascal/BlackBox's precedent for foreign procedure declarations.
`SymbolTable.Mod`/`SemanticActions.Mod` will need to record linkage
information (convention string, optional override name) on such
procedure declarations for both backends to consume.

### Phase 7 — Modules, symbol files (§11, Appendix D4)
`ModuleInterface.Mod`: read/write the textual, DEFINITION-style module
interface format. `SemanticActions.Mod` resolves imports against loaded
interfaces rather than re-parsing source. Module init statement sequence
represented in the tree (lowering to a generated init function/`main` is a
Phase 8 backend concern).
**Testing**: multi-module conformance tests — the Phase-3-deferred
cross-module export-visibility tests land here.
**Milestone**: front end is feature-complete against §3–§11 + Appendix A.
Attempt `poc -check` on poc's own front-end source tree (`Lexer` through
`ModuleInterface`) — parses and type-checks itself, still voc-built, no
codegen yet.

### Phase 8 — LLVM backend, first vertical slice
`LLVMTypes.Mod` (type mapping + Appendix D5 tag/ProcTab/BaseTypes layout,
parameterized by word size), `LLVMCodeGenerator.Mod`,
`LLVMToolchainDriver.Mod` (shells to `llc`/`clang`, 32- and 64-bit
triples). Minimal `rtl/llvm/Console.Mod` for the first runnable "hello
world" — deliberately no GC/pointers/dispatch yet. Straight-line code,
IF/WHILE/CASE, arrays/records only; pointers/`NEW`/dispatch/GC held to
Phase 9. `rtl/llvm/Console.Mod` is the first real consumer of the
external-procedure-declaration extension from Phase 6, since printing a
string means calling out to the host libc (or making a raw syscall) —
this is also the earliest point the NetBSD/OpenBSD/FreeBSD portability
goal becomes concrete, not theoretical.
**Testing**: promote a subset of earlier fixtures from type-check-only to
compile+link+run+diff; cross-check output against voc compiling the same
source where practical. Run the same fixtures on Linux and on at least
one BSD (ideally all three of NetBSD/OpenBSD/FreeBSD) — a distinct `llc`/
`clang` target triple per OS, so this must be verified by actually
running there, not assumed from POSIX compatibility alone.

### Phase 9 — LLVM backend, full parity + self-hosting
Full pointer/`NEW`/GC support (`GarbageCollectedHeap.Mod`,
`ModuleTable.Mod` — bespoke mark-sweep, reusing the type descriptors from
Phase 8), type-bound-procedure dispatch via ProcTab/BaseTypes, open-array
dope vectors, complete `PredeclaredProcedures.Mod` lowering, full
`Out.Mod`/`In.Mod`, 32-/64-bit parity.
**Testing**: entire conformance suite must compile+run+diff on both
32-bit and 64-bit LLVM targets — the explicit gate before VAX/VMS work per
the locked-in sequencing decision.
**Bootstrap milestone**: Stage 0 (voc) compiles all of poc (front end +
LLVM backend) → Stage 1 poc compiles poc's own source again → Stage 2 poc
compiles it a third time; diff Stage 1 vs Stage 2 output for the fixed
point. Once Stage 1 passes the full suite, voc is retired from the
day-to-day build loop and kept only as a comparison oracle.

### Phase 10 — VAX/VMS MACRO-32 backend (scoped, deferred, non-executable)
`VaxTypes.Mod`, `VaxCodeGenerator.Mod`, `VaxToolchainDriver.Mod` (stub
only — no assemble/link/run, per the locked-in decision).
**Explicit scope bound** (to prevent drift): targets exactly Phase 8's
narrow vertical-slice feature set (straight-line code, IF/WHILE/CASE,
arrays/records) — *not* full GC/dispatch parity. "Done" means
hand-reviewed `.mar` output checked into
`test/conformance/*/expected-vax.mar`-style fixtures with a reviewer
rationale comment, not an automated pass/fail. Assembling/linking/running
under SIMH-hosted VMS 5.5-2 is tracked only as a future, undated Phase 11
placeholder — not detailed further here.

**Symbol-name mangling is required, not optional**: VAX MACRO-32 symbols
are limited to **31 characters**. This project's own naming convention
favors longer, descriptive Oberon-2 identifiers (module names, exported
procedure names, qualified `Module.Procedure` forms, type-bound-procedure
dispatch names), which will routinely exceed that limit — unlike the LLVM
backend, which has no such restriction and can emit names close to
verbatim. `VaxTypes.Mod`/`VaxCodeGenerator.Mod` must therefore implement a
deterministic name-mangling scheme (e.g. truncate-plus-hash-suffix) for
every emitted MACRO-32 symbol, and this scheme needs its own fixtures
(long/colliding names deliberately included in the Phase 10 test set) to
confirm two distinct Oberon-2 names never mangle to the same 31-character
symbol.

**External procedures under the VMS Calling Standard**: any procedure
declared external (Phase 6's FFI extension) must be lowered according to
VMS's own well-defined Calling Standard, not poc's internal calling
convention for ordinary Oberon-2 procedures — this is separate work from,
and in addition to, plain MACRO-32 codegen for pure-Oberon code, and its
external-symbol names are subject to the same 31-character limit above.

## Open design questions

- **External procedure declaration syntax**: decided 2026-09-16, grammar/
  symbol-table side implemented in Phase 6 (2026-09-16) — a bracketed
  string-list attribute after `PROCEDURE`, body-less (`PROCEDURE ["C"]
  Name*(...): T;`, optionally `PROCEDURE ["C", "malloc"]
  AllocateBytes*(...): T;` to override the linkage name), per
  `AGENTS.md`'s "External procedures". Needed by Phase 6 for calling C
  functions on Linux/the BSDs, and by Phase 10 for VAX/VMS Calling
  Standard interop. Both backends' actual lowering is still Phase 8/10
  work - Phase 6 only parses the declaration and records its linkage
  info (`SymbolTable.ObjectDesc.externalConvention`/`externalName`).

- **`-OC`-equivalent elementary-type-size model**: resolved 2026-09-16 —
  `MemoryLayout.Mod` now parameterizes size/alignment/offset by two
  independent axes, target word size (32/64 bit, unchanged from Phase 4)
  and elementary-type size model (`sizeModelO2*`/`sizeModelOC*`), mirroring
  voc's own selectable `-O2` (classic 8/16/32/32-bit SHORTINT/INTEGER/
  LONGINT/SET) vs `-OC` (Component Pascal 16/32/64/64-bit) sizes. `REAL`,
  `LONGREAL`, `BOOLEAN`, `CHAR`, and `HUGEINT` don't vary by size model;
  under `-OC`, `LONGINT` and `HUGEINT` both end up 8 bytes but stay
  distinct named types (no aliasing/collapsing between them). poc does
  **not** get its own `-O2`/`-OC` CLI flag yet — `MemoryLayout.Mod`'s only
  caller is `Poc.Mod`'s `-dump-layout` debug/golden-file command (poc has
  no codegen yet), which has no real effect for a flag to govern until a
  backend exists, so it instead prints all four word-size × size-model
  combinations unconditionally. Revisit adding a real `-O2`/`-OC` flag once
  Phase 8's backend needs to pick one, or `.sym` interop with voc's
  `.../C/sym` requires it. When that flag is added, its `Usage` text
  should spell out the names rather than leaving them as bare letters —
  confirmed straight from voc's own `OPM.Mod` help text: `-O2` is
  "Original Oberon / Oberon-2", `-OC` is "Component Pascal". Match voc's
  own wording rather than inventing new phrasing.

- **No `ASSERT`**: `Oberon2.pdf`'s §10.3 predeclared-procedure table has
  no `ASSERT` entry (confirmed against the report; see
  `PredeclaredProcedures.Mod`'s header comment), so poc doesn't have one
  either. Every dialect surveyed beyond the strict report adds one, and
  the dominant convention (Component Pascal, and Oberon+ copying it
  verbatim) is a two-argument overload: `ASSERT(x)` and
  `ASSERT(x, n: INTEGER)`, `x` a BOOLEAN condition and `n` an
  implementation-defined exit/trap code — the report text explicitly
  leaves `n`'s interpretation to the implementation. voc follows this
  same two-arg form as a compiler-recognized special form gated behind
  its `-a` flag (on by default): on failure it prints "Assertion
  failure." (plus `n` if nonzero) and exits with `n` or 0. The one
  outlier is Wirth's own final/"Oberon-07" report, which has only the
  single-argument `ASSERT(b)` with no code parameter. Undecided whether
  poc should add `ASSERT`; if it does, voc's `ASSERT(x)` /
  `ASSERT(x, n: INTEGER)` two-arg form is the better precedent to match
  (also consistent with `HALT`'s existing exit-code convention) —
  possibly with an additional `ASSERT(x, msg: ARRAY OF CHAR)` overload
  taking a message string directly, which no surveyed dialect offers but
  would be more useful at a call site than an opaque integer code. Not
  scheduled to any phase yet.

- **Type guards in designators — two separate gaps**
  (`000-todo.org`'s bare "Type guards in designators?" line refers to
  both): (1) **mid-chain guards** (`v(T).field`, e.g. the report's own
  `t(CenterTree).subnode`) — resolved 2026-09-17. `Parser.Mod`'s
  `ParseDesignator` selector loop now folds `"(" Qualident ")"` in
  directly via a speculative `TryParseGuardSelector` (checkpoint the
  parser, commit to a `GuardSelector` node only when the closing `")"` is
  immediately followed by another selector token — the one shape
  Factor's own grammar, `Designator [ActualParameters]`, proves can
  never be `ActualParameters` instead, since a call's argument list is
  never followed by more selectors; every other shape rolls back
  unchanged, leaving the existing *terminal* guard-vs-call
  disambiguation, `LookupBareTypeName`/`CheckDesignatorExpr`, untouched).
  `CheckDesignator` (`SemanticActions.Mod`) applies the already-existing
  `CheckGuard`/`CheckExtensionApplicable` pair mid-chain via a new
  `GuardSelector` case, sharing a `ResolveTypeName` helper with
  `LookupBareTypeName` and `CheckWithGuard`. Three new conformance
  tests: `semantic-mid-chain-guard`, `semantic-reject-mid-chain-
  guard-not-type`, `semantic-reject-mid-chain-guard-not-extension`. Not
  revisited as part of this fix: several already-committed Phase 3/4
  procedures (`Types.Mod`'s `IsNumeric`/`EqualTypes`/`Extends*`/
  `ArrayCompatible*`/`AssignmentCompatible*`, `MemoryLayout.Mod`'s
  `DescriptorSize`, `SemanticActions.Mod`'s `CheckExtensionApplicable`)
  still bind a guarded value to a local variable before selecting a
  field off it, a workaround this fix makes optional but does not
  require removing — left alone deliberately, since simplifying eight
  call sites in the Appendix A predicates (the semantic crux of the
  whole front end) for a purely cosmetic win isn't worth the risk to
  already-tested code; revisit opportunistically, not as its own task.
  (2) **A qualified `WITH` variable** (`WITH M.v: T DO ...`) — resolved
  2026-09-17, but not the way it was first framed above (extend the
  shadow-`Insert` trick to narrow `M.v` too). Direct experiment against
  real voc found `WITH M.v: T DO` isn't a narrowing gap at all: voc
  rejects it outright (err 245, "guarded pointer variable may be
  manipulated by non-local operations; use auxiliary pointer variable"),
  because an imported module's exported pointer variable could be
  reassigned by any of *that* module's own procedures during the guarded
  body's execution — a real memory-safety hazard (the guard's narrowed
  type could no longer match what the variable actually points to), not
  a convenience gap. `Oberon2.pdf` §9.11 is silent on this either way
  (its grammar, `Guard = Qualident ":" Qualident`, happily allows the
  qualified spelling). Testing every shape directly against voc (not
  guessed at) showed this rejection is broader than just the qualified
  case — voc runs the same "could this be reassigned by a non-local
  operation" check for *every* pointer-typed WITH guard: it also rejects
  a VAR parameter of pointer type (an alias to the caller's storage) and
  a variable assigned by bare name inside some *other* `PROCEDURE`
  anywhere in the module (even one never called from the guarded body —
  a static check, not real call-graph reachability), while accepting a
  local variable, or a module-global, never assigned inside any
  `PROCEDURE` at all. `SemanticActions.Mod`'s `CheckWithGuard` now
  implements the same three rejections (see its own header comment for
  the full case-by-case table and the new `SymbolTable.ObjectDesc.
  isVarParam` field/`CollectProcAssignedNames` whole-module pre-pass that
  back it), deliberately the simpler, strictly *more conservative* half
  of voc's own rule (it doesn't special-case "except this same
  procedure's own straight-line code" the way voc does, so it also
  rejects that one narrow shape voc happens to allow — never less safe,
  only occasionally stricter). Four new conformance tests:
  `semantic-reject-with-qualified-guard`, `semantic-reject-with-var-
  param-guard`, `semantic-reject-with-global-reassigned`,
  `semantic-with-value-param-guard` (the accepting counterpart to the
  VAR-parameter rejection). The RECORD-typed guard case (VAR record
  parameter/receiver) is exempt from all of this and untouched - poc
  doesn't support RECORD guard variables at all yet regardless
  (`CheckExtensionApplicable`'s own header comment, PLAN.md Phase 6
  territory, pre-existing).

- **Predeclared "functions" in constant expressions — really two separate
  gaps, not one**: found 2026-09-17 while running the Phase 7 self-check
  milestone (`poc -check` against poc's own front-end source) —
  `ConstantEvaluator.Mod`'s own `maxHugeInt = MAX(LONGINT);` CONST
  declaration fails with "not a constant expression". `ConstantEvaluator.
  Mod`'s own header comment already documents its scope as deliberately
  narrow ("A ConstExpr's only possible leaves are literals, named constants
  ..., and TRUE/FALSE — never a variable, a call, or a selector"); no
  predeclared name was ever added to that set. Revisiting the framing
  (2026-09-17): `MAX`/`MIN`/`SIZE` are not really *calls* at all in the
  report's sense — their argument position holds a bare *type name*, not
  a value expression (`PredeclaredProcedures.Mod`'s own header comment
  already treats this as a distinct shape for ordinary, non-constant
  type-checking: "MAX/MIN/SIZE take a bare *type name* argument", handled
  by a small local `SymbolTable.Find` + typeClass check rather than
  through the injected `CheckExprProc`). Constant-folding this needs no
  general "evaluate a call's argument, then apply the function" machinery
  at all - just one more `ConstExpr` leaf shape (a predeclared name plus a
  bare type-name argument), resolved directly against a fixed, target-
  independent bound. This is a fundamentally smaller problem than folding
  a *value*-argument predeclared function (`ORD`/`ABS`/`CHR`/`ASH`/`CAP`/
  `ENTIER`/`LONG`/`ODD`/`SHORT`), which genuinely would need the general
  machinery (recursively evaluate the argument via `Evaluate`, then apply
  the function's own value transform) - that piece is deferred, not
  currently blocking anything found so far, and is real, separate,
  future work.
  - `MAX(T)`/`MIN(T)` **implemented** 2026-09-17 for the integer family
    (`SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT`), `SET`, `CHAR` and
    `BOOLEAN` - the same argument set `PredeclaredProcedures.CheckMaxMin`
    already accepts for ordinary type-checking, minus `REAL`/`LONGREAL`
    (see below). Every bound folded is a fixed, target-word-size-
    independent language fact (e.g. `SHORTINT` is always -128..127), so
    there is no default-model ambiguity to resolve first, unlike `SIZE`
    below.
  - `MAX(REAL)`/`MAX(LONGREAL)`/`MIN(REAL)`/`MIN(LONGREAL)` **not**
    implemented - deliberately scoped out of the above. Unlike the
    integer family, the correct bound is an IEEE 754 largest-finite-value
    fact that should be verified against real voc's own actual behavior
    first (this project's standing "verify against voc before
    implementing" convention), not guessed at, and ties into the
    already-tracked correctly-rounded-float-formatting work (see
    `references.md`). Revisit alongside that, not as part of this pass.
  - `SIZE(T)` **implemented** 2026-09-17, but unlike `MAX`/`MIN` its
    result is genuinely target-dependent (word size and elementary-type
    size model - `MemoryLayout.Mod`'s own two axes), and poc has no real
    `-O2`/`-OC`/word-size CLI flag yet to pick one from (see this file's
    own "`-OC`-equivalent elementary-type-size model" entry above).
    Folds using `MemoryLayout.wordSize32`/`MemoryLayout.sizeModelO2` as a
    fixed default, the same "assume `-O2`, poc's existing default absent
    a real flag" precedent `ConstantEvaluator.IntegerLiteralType` already
    established for integer-literal folding (word size 32 chosen to
    match: voc's own `-O2` name means "Original Oberon / Oberon-2",
    historically a 32-bit environment). Revisit once poc gets a real
    `-O2`/`-OC`/word-size flag of its own - the same open item as
    `IntegerLiteralType`'s own default. In practice `SIZE(T)` only works
    for a predeclared or imported `T` right now, never a type declared in
    the *same* module's own `TYPE` section - `CheckModuleBody` resolves
    `CONST` declarations before `TYPE` declarations unconditionally,
    regardless of their relative textual order (this file's own "Relax
    order of declarations" item, `000-todo.org`), a real, concrete
    instance of that already-tracked gap found while testing this.
    Three new conformance tests: `semantic-const-max-min-size`,
    `semantic-reject-const-max-min-too-wide`, `semantic-reject-const-max-
    min-not-a-type`.

- **Constant arithmetic doesn't re-derive its result's minimal type from
  the computed value**: found 2026-09-17 while testing the `MAX(T)`/
  `MIN(T)` work above. `ConstantEvaluator.EvaluateNumericOp` types an
  arithmetic result via `Types.WiderOf(l.type, r.type)` alone (purely
  rank-based, matching Appendix A's arithmetic-operator table), never by
  re-examining the computed value the way `IntegerLiteralType` already
  does for a bare literal token. So `CONST TooWide = MAX(SHORTINT) + 1;`
  (value 128) stays `SHORTINT`-typed in poc, even though 128 does not fit
  `SHORTINT`'s own range - but real voc (confirmed 2026-09-17) rejects
  `s := TooWide` (`s: SHORTINT`) with "incompatible assignment", meaning
  voc *does* re-derive the minimal type from 128 itself. `Oberon2.pdf`
  §5's wording ("the type of an integer constant is the minimal type to
  which the constant value belongs") is about "an integer constant"
  generally, arguably not just a literal token, which would support
  voc's broader reading. Not fixed - found by a test, not by design
  review, and deliberately routed around rather than papered over (see
  `semantic-reject-const-max-min-too-wide`'s own header comment for how).
  Would need `EvaluateNumericOp` (and presumably `EvaluateUnary`'s
  negation case) to re-run something like `IntegerLiteralType`'s own
  digit-range logic against the computed value, not just the operand
  types - worth doing, but a separate, general `ConstantEvaluator.Mod`
  correctness fix, not specific to `MAX`/`MIN`. Not scheduled to any
  phase yet.

## Critical files

- `AGENTS.md` — spec/toolchain context this plan builds on.
- `src/front/Types.Mod` — houses the Appendix A predicates; the semantic
  crux of the whole front end (Phases 3–6).
- `src/front/SemanticActions.Mod` — parser-action/type-check layer
  (Phases 2–7).
- `src/front/ModuleInterface.Mod` — module interface mechanism (Phase 7),
  shared by both eventual backends and by self-hosted poc.
- `test/testenv.sh`, `test/testresult.sh` — golden-file harness (Phase 0),
  reused/extended through every later phase.

## Verification approach

- **Per-phase**: ASSERT-based `.mod` fixtures, generalized from voc's
  `src/test/confidence` layout (one directory per feature area, a `.mod`
  source, a `test.sh`, a golden `expected` file), diffed via
  `testresult.sh`. Favor lifting the report's own inline examples directly
  as fixtures — nearly every construct in `Oberon2.pdf` has a canonical
  example already.
- **Cross-checking**: where practical, compile the same source with `voc`
  and compare behavior/output to poc, using voc as a semantics oracle.
- **Phase 6 exit gate**: explicit checklist against all eight Appendix A
  definitions before moving on.
- **Phase 8/9**: fixtures promoted from type-check-only to actually
  compile+link+run+diff, on both 32-bit and 64-bit LLVM targets.
- **Phase 9 self-hosting**: Stage 1 vs. Stage 2 output diff as the
  fixed-point proof; full conformance suite must pass under Stage 1 before
  voc is retired from the day-to-day build loop.
- **Phase 10**: manual review only (no automated run), explicitly bounded
  in scope as described above.
