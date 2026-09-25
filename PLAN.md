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
| VAX/VMS backend | Phase 13 emits MACRO-32 assembly text only (hand-reviewed, non-executable); assembling/linking/running under VMS 5.5-2 (SIMH or real hardware) was deferred at first and is now Phase 14, ending with poc bootstrapping itself on VAX/VMS; Phase 15 adds VMS library/module support, and Phase 16 has poc write `.OBJ` files itself instead of MACRO-32 text |
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
  binary. This is load-bearing infrastructure through Phase 10, not just
  a reference — until Stage 1 exists, there is no other way to build poc.
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
      VaxToolchainDriver.Mod -- stub only; no assemble/link/run (Phase 13)
  driver/
    Poc.Mod                -- main program; CLI parsing (`poc options {files {options}}`, voc-style)
rtl/
  llvm/
    GarbageCollectedHeap.Mod -- bespoke mark-sweep GC (Phase 9)
    ModuleTable.Mod          -- loaded-module/root registry (Phase 9)
    Console.Mod              -- minimal print-a-string I/O (Phase 10)
    Platform.Mod             -- Chdir/CWD/GetEnv/PID/Unlink/System - voc-compatibility, not Oakwood (Phase 10)
    Files.Mod                -- File/Rider I/O - voc-compatibility + Oakwood basic module overlap (Phase 10)
    Modules.Mod              -- ArgCount/GetArg - voc-compatibility (Phase 10)
    Out.Mod, In.Mod          -- Oakwood basic modules, also a poc-own dependency (Phase 10)
    Strings.Mod, Math.Mod, MathL.Mod -- remaining Oakwood basic modules (Phase 10)
  vax/                        -- deferred stubs only until Phase 14 (minimal runtime), Phase 15 (libraries)
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
| 9 | LLVM full parity | Appendix D5 descriptors, REAL/SET codegen, GC, dispatch, open arrays | LLVM | voc |
| 10 | Oakwood library + voc-compatibility + Appendix C | `rtl/llvm` (`Console`, `Platform`, `Files`, `Modules`, `Out`, `In`, `Strings`, `Math`, `MathL`), `SYSTEM` lowering | LLVM | voc → **Stage 1/2 bootstrap** |
| 11 | Open design questions and TODO backlog | `ASSERT`, `-g` debug metadata, `Err`, chosen language extensions, constant-folding and `.sym` fixes | LLVM | poc (self-hosted) |
| 12 | Library/module support beyond Phase 10 | voc-option triage, static/dynamic library building, voc module inventory and the chosen modules | LLVM | poc (self-hosted) |
| 13 | MACRO-32 | `VaxTypes`, `VaxCodeGenerator`, `VaxToolchainDriver` (stub) | VAX (scoped, unverified) | poc (self-hosted) |
| 14 | Running on VAX/VMS | `VaxToolchainDriver` (real), `rtl/vax` (minimal), VAX backend widened to what poc's own source needs | VAX (assembled, linked, run) | poc on VAX/VMS compiles itself |
| 15 | Library/module support on VAX/VMS | VMS libraries (object, shareable), ported Oberon modules, native VMS libraries, AST support | VAX | poc on VAX/VMS |
| 16 | Direct VAX/VMS object files | `VaxInstruction`/encoder, `VaxObjectWriter` (`.OBJ`), debug/traceback records | VAX (no assembler in the loop) | poc on VAX/VMS |

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

**Goal**: a hand-verifiable path from a single user module (plus a small,
fixed runtime module set) to a running native executable that prints
text — the first point `poc` produces an executable at all, on Linux and
at least one BSD.

**Done.** The full account - design, every step, what was found and
decided along the way, testing - is in `doc/phases/phase-08.md`, under
the same step numbers:

- **1.** Toolchain smoke test, no `poc` code involved.
- **2.** CLI and driver scaffolding
- **3.** Test harness generalization.
- **4.** `LLVMTypes.Mod`.
- **5.** Straight-line codegen: the smallest useful slice.
- **6.** External-procedure FFI lowering + `rtl/llvm/Console.Mod`.
- **7.** Control flow.
- **8.** Fixed-size arrays and records.
- **9.** Runtime traps.
- **10.** Ordinary procedure calls.
- **11.** Predeclared-procedure lowering.
- **12.** General multi-module user programs + program entry.
- **13.** Fixture promotion + portability verification.

### Phase 9 — LLVM backend, full language parity

**Goal**: every language construct `Oberon2.pdf` defines, compiling and
running correctly through the LLVM backend, on both 32-bit and 64-bit
targets, on Linux and at least one BSD — the point at which the *entire*
conformance suite (not just a hand-picked subset, as Phase 8 step 13
promoted) can compile+link+run+diff. Deliberately *not* the point poc can
compile itself — see Phase 10 below for why self-hosting is a separate,
later gate.

**Done.** The full account - design, every step, what was found and
decided along the way, testing - is in `doc/phases/phase-09.md`, under
the same step numbers:

- **1.** Runtime type descriptors (Appendix D5).
- **2.** REAL/LONGREAL arithmetic, literals, and conversions.
- **3.** SET constructors/operators, named STRING constants, and ARRAY-OF-CHAR/RECORD relational comparison.
- **4.** Bespoke mark-sweep GC (`rtl/llvm/GarbageCollectedHeap.Mod`, `ModuleTable.Mod`).
- **4a.** Hidden members in `.sym` files.
- **5.** `NEW` (fixed record/array), `POINTER`, `NIL`, `^` dereference, `IS`/type guards, and the `WITH` pointer guard.
- **6.** Type-bound procedures and dispatch.
- **7.** Open-array dope vectors.
- **8.** Complete `PredeclaredProcedures.Mod` lowering.
- **9.** 32-/64-bit parity sweep.
- **10.** Catching Up.

### Phase 10 — LLVM runtime library (voc-compatibility + Oakwood + Appendix C) + self-hosting

**Goal**: a real `rtl/llvm` module set, written in Oberon-2 and compiled by
poc itself, covering (a) every voc module poc's own source imports (`Out`,
`Modules`, `Files`, `Platform`), (b) the Oakwood basic modules (`In`, `Out`,
`Files`, `Strings`, `Math`, `MathL`; not `XYplane`/`Input`) and (c) the whole
of `SYSTEM` (Appendix C); then self-hosting, since poc's own source needs (a).

**Done.** The full account - design, every step, what was found and
decided along the way, testing - is in `doc/phases/phase-10.md`, under
the same step numbers:

- **1.** `Console.Mod`.
- **2.** `Platform.Mod`.
- **3.** `Files.Mod`.
- **4.** `Modules.Mod`.
- **5.** `Out.Mod`/`In.Mod` (Oakwood's own basic pair).
- **6.** `Strings.Mod`, `Math.Mod`, `MathL.Mod`.
- **7.** `SYSTEM` (Appendix C), full list.
- **8.** Self-hosting bootstrap.

### Phase 11 — Settling the open design questions and the TODO backlog

**Goal**: go back through everything the project has set aside - the
"Open design questions" section at the end of this file, the open
entries of `000-todo.org`, and every "not done" / "not scheduled" /
"undecided" / "revisit" note scattered through `PLAN.md` and `AGENTS.md`
- and give each item a verdict: **decided** (the decision written into
`AGENTS.md`/`PLAN.md` with the evidence it rests on, voc probed and the
report read, not assumed), **done** (implemented, with fixtures), or
**dropped** (with the reason). Nothing leaves this phase as "undecided".
It sits after Phase 10 - poc compiles itself, so a change to the front
end or the LLVM backend is now checked against a real bootstrap - and
before the library work of Phase 12, whose option triage and module
inventory would otherwise be built on unanswered questions.

**Explicit non-goals**: anything Phase 9 step 10 (Catching Up: `CONST`
`ASH`, `CONST` `MAX`/`MIN` of the real types, integer-literal arithmetic
and computed-constant typing) already owns; the `000-todo.org` items about
voc's command-line switches and machine address size/alignment
(`-A44`/`-A48`/`-A88`) and about supporting voc's `eth`/`ooc`/`ulm` RTLs,
which are Phase 12 steps 1, 3 and 4 by design and stay open until then;
and any VAX/VMS work. Poc's own source stays strict `Oberon2.pdf` Oberon-2
throughout (`PLAN.md`, "Bootstrap terminology"): every language extension
adopted here is implemented in the compiler and tested with fixtures, but
poc's own modules never use it, so Stage 0 (voc) keeps building poc.

**The items** (the inventory step re-checks this list against the tree
as it stands when the phase starts, and adds what it finds):

| Item | Source | Kind |
|---|---|---|
| Value-argument predeclared functions in a `CONST` (`ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`, `LONG`, `SHORT`, `ODD`) - `ASH` is done | Open design questions | gap, "real, separate, future work" |
| A computed `REAL`/`LONGREAL` constant of extreme magnitude (`MAX(LONGREAL) / 2`, `1.0D300 * 1.5`) cannot be exported to a `.sym`: `ParseReal` is not correctly rounded, so no text verifies | Phase 9 step 10 | bug, found not fixed |
| `Out.Real`/`Out.LongReal` are voc's algorithm, not correctly rounded (a decimal exponent estimated as 77/256 of the binary one, scaling by a floating-point power of ten exact only to 10^22): the last digits of a number outside about 10^-22..10^22, or the 17th of a LONGREAL, can be off. The same shortcoming as `ParseReal`'s; one correctly rounded converter each way would close both | Phase 10 step 5 | gap, found not fixed |
| `ENTIER` of a real beyond a `LONGINT` gives garbage (poc: `-2147483648`; voc, which wraps: `-727379968` for 10^12 under `-O2`): the report defines `ENTIER` for values that fit, but a `HUGEINT`-valued one - or a trap - would be kinder | Phase 10 step 5 | **done 2026-09-21** (step 3: a trap, exit 8) |
| Nested procedures (a procedure declared inside another) were not lowered by the LLVM backend: a declaration or a call was a compile error (2026-09-20; before that a comment in the IR and a program quietly missing the call). `Oberon2.pdf` §10: "procedure declarations may be nested". Done in Phase 11 step 8 (2026-09-20/21): lambda lifting by reference, `doc/nested-procedures.md`; what a program can observe is in `AGENTS.md` ("Nested procedures") | Phase 10 step 6; found 2026-09-20 | **done** |
| `LONG`/`SHORT` reject `SYSTEM.INT8..INT64` ("requires a SHORTINT, INTEGER, or REAL argument"); voc's go by size along the model's chain (`OPT.ShorterOrLongerType`) | Phase 10 step 8 (fixed-width `INTn`, 2026-09-20) | gap |
| Under `-OC` an `INT8` met by an integer literal in an expression (`b + 1`) is a `SHORTINT` - the literal's own type is at least two bytes there - and cannot be assigned back to an `INT8` without `SYSTEM.VAL` | Phase 10 step 8 (fixed-width `INTn`) | done 2026-09-21 (step 3) |
| `SYSTEM.SET32` is `SET` (the `-O2` width, 64 bits under `-OC`) and there is no `SET64`: the fixed-width sets `INT8..INT64` got | Phase 10 step 8 (fixed-width `INTn`); `000-todo.org` | **done 2026-09-21** (step 6, with `HUGESET`) |
| `LONGINT` is included in `SYSTEM.ADDRESS` by rank, so on a 32-bit target under `-OC` a mixed `ADDRESS`/`LONGINT` operation is done at the address's 32 bits and truncates the 64-bit operand: `size <= MAX(LONGINT)` in `Files.Old` compared against -1 and no file opened (worked around there, not fixed) | Phase 10 step 8 (fixed-width `INTn`) | bug, found not fixed |
| `SYSTEM.PTR` cannot be dereferenced, guarded, `IS`-tested or a `WITH` variable (voc allows some); a guard followed by an index, or to a pointer-to-array type, is unsupported in the backend | Phase 10 step 7 | decision, gap |
| `BIT`'s word-based meaning (voc's) differs from the report's `Mem[a]` bit; `SYSTEM.NEW` blocks are untraced by the collector | Phase 10 step 7 | decision |
| A constant `NEW` length <= 0: poc traps at run time, voc rejects it at compile time | `000-todo.org`; Phase 9 step 7 | decision |
| An option to make `NEW` trap when the heap cannot satisfy it (today: the pointer is NIL) | `000-todo.org`; Phase 9 step 5 | decision + implementation |
| `ASSERT`: add it or not, which form, and what `-a` means | Open design questions | decision (+ implementation) |
| The collector scans the stack conservatively - can it do better? | `000-todo.org` | investigation |
| Debugging support: `gdb`/`lldb` on poc-built programs | `000-todo.org` | implementation |
| More than 8 open dimensions; copying a value open-array parameter that is never written | Phase 9 step 7 | decision |
| Hand-written guard-then-selector workarounds in the Appendix A predicates | Open design questions | close |
| The optional exported-view-only `-show-interface` | Phase 9 step 4a | decision |
| `HUGESET` (is `SET` already as wide as `LONGINT`?) | `000-todo.org` | decision |
| Relaxing assignment-compatibility rule 6; assigning an `ARRAY OF CHAR` to another (`fileName := name`); other array types | `000-todo.org` (three overlapping entries) | decision + implementation |
| `CONST`/`TYPE`/`VAR`/`PROCEDURE` in any textual order | `000-todo.org` | decision |
| Initializers on `VAR` declarations (`x: INTEGER := 0`) | `000-todo.org` | decision + implementation |
| Record and array literals | `000-todo.org` | decision + implementation |
| Underscores and dollar signs in identifiers (VMS) | `000-todo.org` | decision + implementation |
| An `Err` module (`Out`, writing to standard error) | `000-todo.org` | implementation |
| BSD runs skipped while the BSD hosts were unreachable | Phase 9 step 8 | verification |

1. **Inventory and reconciliation.** Walk the three sources above and
   produce the table as a file (or in this section), one row per item:
   what it is, where it came from, what it blocks (if anything), kind,
   and the verdict once it has one. Reconcile `000-todo.org` with what
   the plan already says: it still lists "Implement constant folding on
   integer literals" as a TODO though Phase 9 step 10 owns it; three of its
   extension entries overlap (rule 6, `ARRAY OF CHAR` assignment,
   `fileName := name`); and "`CONST`/`TYPE`/`VAR`/`PROCEDURE` in any
   order" was half done on 2026-09-17 (sections of the first three may
   interleave; see "Declaration order" below). Ask the user about the
   items whose intent the file does not pin down (see step 6) before
   spending time on them.
   - *Done (2026-09-20).* The inventory is `doc/phase-11-inventory.md`: the 27
     rows of the table above (A), five items only the step text names (B),
     thirteen `000-todo.org` entries the table lacks (C) and nine notes from
     Phases 8-10 in neither (D), each with source, owning step, kind and a
     verdict (`done`, `proposed`, `open`, `phase 12`, or `decided (user,
     date)`). It found four table rows no step owns (`Out.Real` rounding, `ENTIER`
     beyond `LONGINT`, the `SYSTEM.PTR` limits, `BIT`/`SYSTEM.NEW`; A3, A4,
     A10, A11: to be given a step, or dropped, when step 2 starts), two
     bugs still present that the plan only mentioned in passing (a type used on
     the line it is declared on is rejected as a forward reference; `SHORT`
     rejects a `HUGEINT`), and two it could not confirm (a procedure-local record
     without a descriptor, a record type text cut at 63 characters). `000-todo.org` is
     reconciled: the rule-6 entries merged and the `111 < n` paste error
     fixed, the stale `fileName := name` duplicate dropped, the declaration-order
     entry split, ten entries added for what was only here. (The remark above
     that integer-literal folding is still a TODO was already out of date: it
     is `DONE`.) User verdicts so far: a compiler switch for `NEW` on an
     exhausted heap (A13); file and line reporting for traps as a compiler
     switch, off by default, separate from step 5 (C7); documenting what poc
     does and does not trap (C9, **done 2026-09-21**: `AGENTS.md` "What traps,
     and what does not", fixture `llvm-no-trap-behavior`; it found six things,
     all decided with the user and done: see `000-todo.org`); no change to the deliberately silent
     `SIGFPE`/`SIGSEGV`/`HALT(n)` endings (C6); and surveys of other Oberon
     and Oberon-2 compilers before deciding overflow/underflow behavior (C5,
     **done 2026-09-21**: `doc/overflow-survey.md`; decided with the user: no new
     checks - integer overflow wraps and is documented as doing so, reals are
     IEEE and silent, `DIV`/`MOD` by zero stays `SIGFPE`, `SHORT`/`CHR`/`SET`
     element range stay unchecked, an optional `-r` left to Phase 12 step 1;
     `AGENTS.md` "Overflow, division and reals", fixture `llvm-overflow-wrap`) and
     rule 6 with `ARRAY OF CHAR` assignment (A21, **done 2026-09-21**:
     `doc/array-assignment-survey.md`; rule 6 stays, voc's array rule is
     adopted for every element type, an open array is never assigned - which
     fixed a defect - and an open source too long for its target traps, exit
     9; `AGENTS.md` "Array assignment"). The remaining items keep
     their `proposed`/`open` verdicts until their steps run.

2. **Known defects and unfinished corners.** Small, concrete, each with a
   fixture that fails first.
   - *Done (2026-09-20): `FormatInt`.* It negated its argument, impossible at
     the smallest `LONGINT`, so `MIN(HUGEINT)` (and `MIN(LONGINT)` under `-OC`,
     as wide) was written as a bare `-`. It now takes the digits from
     `q = -(x + 1)` as `AppendLongInt` does. That exposed a second problem the
     first fix could not see: the digits `9223372036854775808` are a numeral
     no type holds, so the reader refused its own file ("integer literal too
     large for HUGEINT"); `PrintConstValue` now writes `-9223372036854775807 -
     1` for that one value. New fixture `module-interface-min-values`, which
     also reads each `.sym` back as source, under both size models; the value
     was checked to survive an import at run time.
   - *Done (2026-09-20, decided with the user): a `.sym` can carry a number
     that depends on the target, and that stays.* A `CONST` folded from `SIZE(T)`
     of a pointer or a size-model `MAX`/`MIN` is printed as its folded value, and
     `-emit-interface` writes it for the `-target` and size model it was given
     (`4/8/2147483647/31` at 32 bits `-O2`, `8/16/.../63` at 64 bits `-OC`,
     and so on). What makes it safe: a `.sym` carries no *layout* (the hidden
     declarations are source; the importer computes offsets itself), and every
     whole-program command (`-emit-llvm-ir`, `-build`) regenerates each
     import's `.sym` for its own target and size model, so a client never sees
     a foreign one; only `-check` of a client, which reads whatever is on
     disk, could, after an `-emit-interface` with different flags. Options not
     taken: print the expression rather than the value (needs a dependence flag
     through folding and a way to keep the unexported constants it names), or
     reject the combination. `AGENTS.md`'s "target-independent `.sym`" now says
     "carries no layout". Fixture `module-interface-target-constants` pins
     both halves: the four (word size, size model) values, and a 32-bit
     `lib.sym` regenerated by a 64-bit `-emit-llvm-ir`.
   - *Done (2026-09-20, decided with the user): `ParseReal` is correctly
     rounded* (option (a) below), and extreme computed reals export. New
     module `DecimalToDouble.Mod`: no floating-point arithmetic decides a
     digit. The numeral is a big integer D and a decimal exponent a; the
     nearest double m * 2^e (m of 53 bits, ties to even, subnormals and the
     overflow threshold included) is found by cross-multiplying instead of
     dividing - "q <= V / 2^e" is "L >= q * F" for two big integers built from
     D, 5^|a| and a power of two - with a binary search for q and one
     comparison of 2L with (2q+1)F for the rounding, on 15-bit limbs (integer
     multiply, add and compare only, so nothing depends on the host's
     floating-point width). The reverse direction, `DecimalToDouble.Digits`,
     is exact too: v = m * 2^e is the integer m * 2^e or m * 5^-e with the
     point moved, so its full decimal expansion is the digits of a big integer,
     rounded to any precision, ties to even. `ModuleInterface`'s formatter is
     now "the shortest precision whose text `ParseReal` reads back exactly",
     at most 17 digits, verified; its search of neighbouring digit strings,
     `Pow10`, `RoughExponent`, `RoundedDigitsValue` and `IntToDigits` are gone.
     Checked against Python's `float()`: `llvm-real-parse-rounding` has 364
     literals (midpoints, ties, the largest and smallest normal and
     subnormal numbers, the overflow boundary, random 1-25 digit numbers of
     every magnitude) and the old routine got 249 of them wrong;
     `module-interface-extreme-reals` exports 15 computed constants of extreme
     magnitude, all equal to Python's shortest repr, and reads the `.sym` back
     to an identical one. The old export of `4.94D-324 * 3.0D0` was wrong
     (`1.3D-323`, now `1.5D-323`). Not done: a REAL literal is still parsed to
     a double first (`realVal`), its exact single-precision rounding left to
     LLVM through `realText`; `Out.Real`/`Out.LongReal` are the next bullet.
   - **A3, done (2026-09-20): `Out.Real`/`Out.LongReal` are correctly
     rounded** (the user asked for it ported rather than dropped as a voc
     compatibility). `rtl/llvm/RealDigits.Mod` is `DecimalToDouble.Digits`
     over `HUGEINT` limbs: the digits of the exact m * 2^e, rounded to the
     precision asked (nearest, ties to even), no floating-point arithmetic
     and so no dependence on the size model or the host. It stays a
     separate module because poc's own source may not use `HUGEINT`/`SYSTEM`,
     and Stage 0 has no way to link a runtime module for voc. `Out` keeps
     voc's layout; a subnormal now prints its digits, the whole-part
     workaround is gone, and the exponent is right where voc's estimate was
     off by one (voc printed `1.0E-21` for the REAL nearest 1E-20, and
     `1.0D+299` for the product of 300 tens). Fixture `llvm-real-digits`
     checks 1080 lines against a Python oracle (`generate.py`, committed);
     the old routine gets 261 of them wrong. `llvm-out`, which requires the
     same output from voc and poc, now holds only numbers voc prints
     correctly; the ones it gets wrong went to `llvm-out-extra`.
   - The plan text of the item above: export extreme computed real constants: tier 2 of `ModuleInterface`'s
     real formatter searches for decimal text that `ConstantEvaluator.
     ParseReal` reads back exactly, and for a value like `1.5D300` written
     as `1.0D300 * 1.5` none does (the bound itself, `MAX(LONGREAL)`, is
     handled by name since Phase 9 step 10). Either make `ParseReal`
     correctly rounded - `references.md` lists Clinger and Steele-White for
     exactly this - or export such a constant as an expression, or refuse
     it with a clear message instead of the current "failed to find a
     round-trip-safe text representation".
   - *Done (2026-09-20, decided with the user): fold them.* `ConstantEvaluator.
     EvaluateValueFunction`, reached from `EvaluateDesignator` and
     `IsConstantDesignator`, and `GenerateExpr` folds an integer-typed call of
     them like `ASH`. voc probed under both models with a 51-row table (the
     inventory's A1 row had the outline); the results agree on every row but
     four, which poc leaves as the report has them (`LONG(LONGINT)`,
     `SHORT(SHORTINT)`, voc's one-byte constants under `-OC`) or does better
     (`ENTIER(3000000000.5D0)` under `-OC`, where voc dies of a `Halt(-8)`).
     The types: `ORD` an `INTEGER`, `ABS` of an integer the minimal type of its
     value, `ENTIER` a `LONGINT`, `LONG`/`SHORT` the checker's. Two things the
     probe turned up: voc's `CAP` masks with 0x5F, so `CAP("7")` is 17X there
     (poc's leaves a non-letter alone, as its generated code does; recorded in
     `AGENTS.md`'s known voc bugs), and `SHORT` of an integer constant is
     always an error in poc, since a constant's minimal type never leaves its
     value room in the shorter one. Fixtures `semantic-const-value-functions`
     (the type table), `semantic-reject-const-value-functions` (the
     diagnostics) and `llvm-const-value-functions` (the values, both models,
     run). The plan text: fold value-argument predeclared functions in `CONST`s, sharing what
     Phase 9 step 10 built for `ASH`: recursively evaluate the argument,
     apply the function's own value transform. Probe voc for each one - which
     it folds, and what it rejects (`CHR` of a value out of range, `ENTIER`
     of a value that does not fit) - and match it.
   - *Done (2026-09-20, decided with the user: option 1, place `ADDRESS` by
     its actual byte width).* `Types.Order` gives `SYSTEM.ADDRESS` the place a
     `SYSTEM.INTn` of the target's word size would have (`Types.
     SetAddressBytes`, fed by `ConstantEvaluator.SetWordSize`); fixtures
     `semantic-address-width` (assignability and the mixed-sum type at both
     word sizes and models) and `llvm-address-width-ir` (`a <= MAX(LONGINT)`
     on i686 under `-OC` is an `icmp` at i64). A sweep of `rtl/llvm` under
     i686/x86_64 x `-O2`/`-OC` found what the check now rejects on 32-bit
     `-OC`: seven sites passing a `LONGINT` length or offset to a `size_t`/
     `long` parameter (`Console.Mod`, `Platform.Mod`, `Files.Mod`), now
     `SYSTEM.VAL(SYSTEM.ADDRESS, ...)`, and `Files.Old`'s `HUGEINT` workaround
     went back to the plain `size <= MAX(LONGINT)`. Run on Linux
     (2026-09-20, with `glibc-devel.i686`): the Stage 0 poc built poc itself
     as a 32-bit `-OC` executable (`-OC -target i686-unknown-linux-gnu`, 5 s);
     that i686 poc, run on the x86_64 target, rebuilt poc with every `.ll`,
     every `.sym` and the executable byte for byte those of Stage 1, and the
     whole suite (219 fixtures) passes under it. Still to run: the same on a
     BSD host (unreachable from home) - done 2026-09-21 on the local OpenBSD
     i386 VM (`cymoril`): its voc-built Stage 0 built poc there as a 32-bit
     `-OC` executable (Stage 1, 10 s), which rebuilt itself (Stage 2: every
     `.sym`, the `Poc.ll` and the executable identical), the `Poc.ll` is
     byte for byte the Linux cross-compile for `i386-unknown-openbsd7.9`
     (`-OC -target ...  -emit-llvm-ir`), and all 237 fixtures pass under it.
     (`tools/bootstrap/stage1` now sets voc's library path itself, as
     `test/testenv.sh` does: a non-interactive `ssh` on a BSD found no
     `libvoc-OC.so` for the voc-built Stage 0 poc.) The plan text follows.
   - *`LONGINT` included in `SYSTEM.ADDRESS`, at a width it does not fit.*
     `Types.Order` puts `ADDRESS` between `LONGINT` and `HUGEINT` by rank,
     whatever the target: right when both are 32 bits or `ADDRESS` is 64, wrong
     on a 32-bit target under `-OC`, where `LONGINT` is 64 bits and a mixed
     comparison or arithmetic operation is emitted at `i32`, truncating it
     (`AGENTS.md`: "a `LONGINT` can be assigned to an address"). The fixture
     that fails first is a program built with `-OC -target i686-...` that
     compares an `ADDRESS` with `MAX(LONGINT)`; `llvm-i686-runtime`'s
     `i686_can_run`/`i686_triple` run it for real where a 32-bit runtime
     exists, and the IR is golden-checkable everywhere. Two ways out, decide
     between them: place `ADDRESS` by its actual byte width the way `INTn`
     are (`Types` would learn the word size as it learned the size model, via
     `ConstantEvaluator.SetWordSize`; but then a `LONGINT` is no longer
     assignable to an `ADDRESS` on that target, and the runtime's few uses need
     `SYSTEM.VAL`), or keep the hierarchy for assignment and do a mixed
     *operation* at the wider actual width. Either way sweep `rtl/llvm` for
     the same shape (only `Files.Old` was found, by grepping `MAX(LONGINT)`;
     `Files.Mod` compares through `SYSTEM.VAL(HUGEINT, ...)` meanwhile).
   - *Done (2026-09-20): `LONG` and `SHORT` of `SYSTEM.INT8..INT64` and of
     `HUGEINT`* (also the "`SHORT` rejects a `HUGEINT`" bug, `doc/phase-11-
     inventory.md` D1). Probed against voc under both models with a matrix
     over every integer type; poc's result types are identical for the eight
     `SYSTEM.INTn`/`HUGEINT` operands (28 rows), and differ only where poc
     keeps the report: `LONG(LONGINT)` and `SHORT(SHORTINT)` stay errors, voc
     accepts them. `Types.IntegerBytes`/`LongShortByWidth`/`LongerInteger`/
     `ShorterInteger` hold the rule, used by both `CheckLong`/`CheckShort` and
     `GenerateLong`/`GenerateShort`; `SYSTEM.ADDRESS` is not chained (its width
     is the target's). Fixtures `semantic-long-short-width` (the table, every
     type under both models) and `llvm-long-short-width` (the values), and the
     two rows of `semantic-system-fixed-width` changed as predicted. The
     earlier plan text follows. voc's rule (read in
     `OPT.ShorterOrLongerType`, 2026-09-20; probe it before relying on this
     summary) goes by *size along the size model's own chain*: `LONG(x)` of
     an integer is the narrowest of `SHORTINT`/`INTEGER`/`LONGINT` strictly
     wider than `x`, else `INT64`; `SHORT(x)` the widest strictly narrower,
     else `INT8`. So `LONG(INT32)` is a `LONGINT` under `-OC` and an `INT64`
     under `-O2`, and the result is a model type, not an `INTn` of the next
     width. poc's `CheckLong`/`CheckShort` (`PredeclaredProcedures.Mod`) and
     `GenerateLong`/`GenerateShort` (`LLVMCodeGenerator.Mod`) identify their
     operand by type identity (`SHORTINT`, `INTEGER`, `LONGINT`, `REAL`
     only) and refuse anything else, so both grow a size-driven branch for a
     fixed-width operand; the two `LONG(i)`/`SHORT(q)` rows of
     `semantic-system-fixed-width` record the current refusal and change with
     it.
   - *Done (2026-09-20): a type used on the line it is declared on.* `A =
     INTEGER; B = ARRAY 3 OF A;` on one line was rejected as a forward
     reference: `SemanticActions.ResolveQualidentType` and `ConstantEvaluator.
     LookupBareTypeName` compared only the declaration's line with the use's
     (`doc/phase-11-inventory.md` D2, found in Phase 9 step 1). Both now call
     `SymbolTable.DeclaredAtOrAfter`, which compares the column too. voc
     accepts the backward use and rejects the forward one (`B = ARRAY 3 OF A;
     A = INTEGER;`); the self-referencing `S = ARRAY 3 OF S` was reported as
     a forward reference only by accident of the line-only test and is now the
     cyclic-declaration error (voc: "recursive type definition"). Fixtures
     `semantic-same-line-type-use`, `semantic-reject-same-line-type-cycles`;
     the `SIZE(T)` line of the first fails without the `ConstantEvaluator`
     half.
   - *Done (2026-09-20): a construct the LLVM backend cannot lower is an
     error.* Every one of `LLVMCodeGenerator.Unsupported`'s 34 sites wrote a
     `; unsupported` comment into the IR and let the build succeed - a program
     quietly doing less than its source. Now each is an error naming module and
     statement line (`ReportUnsupported`), `GenerateProgram` counts them
     (`unsupportedCount`), and `EmitIR`/`Build` write nothing when any was met.
     Poc's own IR and every fixture's had none, so nothing else moved. New
     fixture `llvm-reject-nested-procedure` (since renamed
     `llvm-reject-external-vms`, once nested procedures were lowered).
   - *Nested procedures.* The feature the change above makes visible: now
     step 8 below, planned in `doc/nested-procedures.md`.
   - *Done (2026-09-20): exit status.* `poc` returned 0 whatever happened, so
     `make` and scripts could not tell a failed build from a good one. A
     module-level `failed` in `Poc.Mod` is set at every place a failure is
     reported (every "poc: ..." message, bad usage, the unsupported-construct
     summary), and after `Run` the process ends with `Platform.Exit(1)` if it
     is set or `Diagnostics.errorCount` or `LLVMCodeGenerator.unsupportedCount`
     is nonzero. `Platform.Exit(code: LONGINT)` is voc's, which
     `rtl/llvm/Platform.Mod` now has too (C `exit`, which flushes stdio); the
     poc built by voc and the one built by poc behave alike. New fixture
     `poc-exit-status` (18 command lines, status only). The bootstrap scripts
     (`set -e`) now stop on a failing `poc`. Found on the way: an unregistered
     `Files.New` file is left behind as `.tmp.<n>.<pid>` in both runtimes, and
     voc's `Files.Delete` renames rather than unlinks, so a failed `-emit-llvm-ir`
     registers its file and `Platform.Unlink`s it (which also removes a stale
     `.ll` from an earlier run); the two new fixtures fail on a leftover temp
     file, and `.gitignore` covers them.
   - Close the two "revisit opportunistically" notes by decision, not by
     work: the guard-then-selector workarounds in `Types.Mod`,
     `MemoryLayout.Mod` and `SemanticActions.Mod` stay as written (they
     are correct, tested, and rewriting the Appendix A predicates for style
     is a risk with no payoff - decided with the user 2026-09-20, and
     recorded in `AGENTS.md` where the workarounds are described);
     `-show-interface` is built (below).

   - *Done (2026-09-20, the user wanted it built): `poc -show-interface
     <file>`.* Prints a checked module's exported view on standard output, as
     voc's `showdef` does: exported constants, types, variables and
     procedures, and of each record only its exported fields and type-bound
     procedures (a `.sym`, which since Phase 9 step 4a carries the hidden
     ones too, no longer serves as that view). It is `ModuleInterface.Write*`'s
     own printers with `exportedView` set (`ModuleInterface.Show`), so the two
     cannot disagree on how a declaration reads; a procedure is a plain
     `PROCEDURE` heading, not the `.sym`'s body-less `PROCEDURE^`; an
     unexported type an exported signature mentions is named, not declared, so
     the view is for reading and is not source an importer could check. Like
     `-emit-interface` it needs the imports' `.sym` on the import path and
     writes nothing. Fixture `module-show-interface` (a module with hidden
     fields, methods, types, constants, variables and procedures, next to its
     `.sym`, and an importer). `-import-path`, `-target` and `-O2`/`-OC` apply
     as for `-emit-interface`.

3. **Run-time semantics.** Each of these is a place the report is silent
   and voc chose something; the step probes voc, writes down what it does
   and what poc does, and decides.
   - *Done (2026-09-21): an integer literal next to a `SYSTEM.INT8`, under
     `-OC`.* voc's rule, read in `OPB.Op`/`OPT.IntType` and probed under both
     models (a matrix of `+ - * DIV MOD`, comparisons, `INC`/`DEC`, `FOR`,
     `CASE`, arguments and `RETURN` over `INT8`..`INT64`, `SHORTINT`, named
     constants and constant subexpressions): voc types every constant by the
     fewest bytes its value needs whatever the model (`b + 1` is an `INT8`
     under `-OC`), and a constant that does not fit leaves the sum at the wider
     type, so `b + 127` compiles and `b + 128`/`b + 200` do not. poc keeps its
     model-minimal constant types (they show elsewhere) and adds only the
     adoption: `Types.ConstantAdoptsType(constType, otherType, value)` - an
     integer constant whose type is wider than a `SYSTEM.INTn` operand's, and
     whose value fits it, takes it - applied where the operation's type is
     chosen, `SemanticActions.AdoptConstantOperandType` in `CheckBinaryExpr`
     and `LLVMCodeGenerator.AdoptConstantOperands` in `GenerateBinaryExpr`
     (re-emitting the constant, always one immediate, at the other's type), for
     `+ - * DIV MOD` only: a comparison's BOOLEAN result and the fit make
     widening the other operand equivalent. Every probed line accepts or
     rejects as voc does. **Found on the way:** `CASE` on an `INT8` under `-OC`
     built invalid IR (`sext i16 1 to i8`; a label constant is at least two
     bytes there), the same for a one-byte `SHORTINT` under `-O2` with a label
     above 127, because the checker never compared a label with the selector's
     range; voc rejects such a label (err 60), so poc now does
     (`CaseLabelFits`; both ends of a range, where voc looks only at the low
     end) and the code generator narrows a label with `trunc`. Fixtures
     `semantic-system-fixed-width` (21 rows), `llvm-system-int8-constants`
     (poc and voc, both models, one output), `semantic-case-label-range`. The
     earlier plan text follows. A constant's
     type is the minimal one its value fits *under the size model*, which under
     `-OC` is never narrower than `SHORTINT`'s two bytes, so `b + 1` for an
     `INT8` `b` is a `SHORTINT` and `b := b + 1` is refused (a constant *by
     itself* is already assignable to an `INTn` if its value fits, via
     `Types.FixedIntFits`). Probe voc: how does it type a constant met by a
     narrower operand, and does `b := b + 1` compile there under `-OC`? The
     likely rule to adopt is that a constant operand takes the other operand's
     fixed-width type when its value fits it. It has to be applied in two
     places that each pick the operation's type from `Types.WiderOf` on types
     alone - `SemanticActions.CheckBinaryExpr` and `LLVMCodeGenerator.
     GenerateBinaryNumeric`/`GenerateRelational` (whose callers, unlike they,
     hold the expression node to test for constness) - or the two disagree.
   - *A constant `NEW` length <= 0.* voc rejects it at compile time
     ("illegal value of constant"); poc's `NEW` traps at run time (exit 7)
     for any non-positive length. Default to matching voc - reject a
     constant one in `PredeclaredProcedures.Mod` with a diagnostic naming
     the argument - and keep the run-time trap for non-constant lengths.
   - *`NEW` on an exhausted heap.* Today the pointer is left NIL and the
     next dereference traps (voc's behavior). Decide whether a switch for
     "trap right at the `NEW`" is wanted, and what shape it takes: a
     compile-time flag that lowers `NEW` to a checking entry point (the
     natural fit with voc's own switch style and with Phase 12 step 1's
     option table), or a run-time setting in `GarbageCollectedHeap`.
     Implement the one chosen; the trap gets its own exit status and text,
     documented next to the existing ones.
   - *`ASSERT`.* Resolve the open question with its own survey already in
     hand (every dialect adds one; the dominant form is `ASSERT(x)` and
     `ASSERT(x, n)`, `n` an implementation-defined code; voc gates it
     behind `-a`, on by default; Wirth's Oberon-07 has only `ASSERT(b)`).
     Recommended: adopt voc's two-argument form, lowered as a trap with
     its own exit status when `x` is FALSE and `n` reported, and decide in
     the same step whether `-a` (assertions off) is worth having and
     whether the message-string overload is - no surveyed dialect has it.
     If adopted it becomes the twenty-first predeclared procedure, so
     `PredeclaredProcedures.Mod`, the LLVM lowering, the `Usage` text and
     `AGENTS.md`'s "the report has no `ASSERT`" note all change; fixtures
     cross-check the two-argument form against voc.
     **Done 2026-09-25** (user): as recommended, `doc/assert-survey.md` has
     the survey and the decision - both forms, `n` a constant in 0..255, a
     trap with status 10, a constant FALSE condition a compile-time error,
     no switch, no message-string form; fixtures `llvm-assert`,
     `semantic-reject-assert`.
   - *Open-array limits.* Decide whether more than 8 open dimensions is
     worth supporting (voc's own limit is the thing to look up) and
     whether skipping the copy of a value open-array parameter that the
     procedure never writes is worth doing; the second is a code-size
     and speed matter, so it needs a use of the parameter analysis the
     compiler does not yet have - drop it unless a measurement says
     otherwise.
   - *`ENTIER` of a real beyond a `LONGINT`* (inventory A4, given to this step
     2026-09-20). Today poc gives garbage (`-2147483648`) and voc wraps
     (`-727379968` for 10^12 under `-O2`); the report defines `ENTIER` only for
     a value that fits. Decide between a `HUGEINT` result (a constant
     `ENTIER` folded in a `CONST` already rejects what does not fit, per voc)
     and a run-time trap in the style of this step's other traps; probe voc
     under both models first, and let A1's `CONST` folding follow the choice.
     **Done 2026-09-21, decided with the user: a trap.** voc's `SYSTEM_ENTIER`
     is a bare C cast (32-bit wrap under `-O2`, INT64_MIN under `-OC`); the A2
     and Oberon V4 compilers (`fistp`) and obc do not check either, and all type
     the result as the standard integer type, as do the report, Component Pascal
     and (as `FLOOR`) Oberon-07. So the result stays `LONGINT` (a `HUGEINT` one
     helps only `-O2` and breaks `n := ENTIER(x)`), and `GenerateEntier` checks
     the range first - 2^(w-1) as an exact float bound, ordered compares so a NaN
     fails - and traps, exit 8, "ENTIER argument out of range for LONGINT"
     (`entierTrapGlobal`, `needEntierTrap`); the `fptosi` it replaces was poison
     for such a value. The `CONST` folder already rejected the same values at
     compile time. Fixture `llvm-entier-trap`; `AGENTS.md` has the behavior.

4. **Can the collector do better than scanning the stack conservatively?**
   An investigation with a written answer. The collector already traces
   heap blocks through their type descriptors; only the stack (and
   registers) are scanned without type information, so the questions are
   what that costs and whether fixing it is worth it. Measure first: a
   fixture that builds structures, drops them, and counts what survives a
   collection at both word sizes (a false pointer is likelier with 32-bit
   words), and the run time of the collector on poc compiling itself.
   Then lay out the options with what each needs - keep conservative
   scanning and document its limits; a shadow stack of live pointer roots
   maintained by the generated code; LLVM's own `gc`/statepoint stack
   maps - and their cost in generated-code size and in portability to the
   four Unix-likes (and, later, VAX/VMS, where the backend has no LLVM
   to lean on: the answer must not be one the VAX backend cannot follow).
   voc's own runtime is the comparison. The default outcome is "keep it,
   documented"; anything more is a separate, sized proposal, not work done
   in this step.

5. **Debugging support for `gdb` and `lldb`** (both are installed).
   Emit LLVM debug metadata from `LLVMCodeGenerator` under a new `-g`
   option, in stages, each ending with a fixture that drives the debugger
   in batch mode and checks its output:
   (a) line tables and subprogram names - a breakpoint on
   `Module.Procedure` and a backtrace of Oberon frames with source lines,
   which needs every AST node's line and column carried down to the
   instructions the generator emits;
   (b) parameters and locals of the basic types, so `print`/`info locals`
   show values;
   (c) records, arrays, pointers, and type-bound procedures - a record
   printed field by field, with Oberon type names;
   (d) what the calling convention hides: a `VAR` record's type tag and an
   open array's lengths presented as one variable, not as extra
   parameters. Decide how far to go from what the debuggers' DWARF
   support can express, and record what is left out. The source
   positions and the type descriptions built here are also the inputs
   Phase 16 step 5 needs for the VAX debug and traceback records, so they
   are kept in a form the second backend can read, not folded into the
   LLVM emitter.

6. **Language-extension decisions.** Each item below is a decision first;
   the implementation follows only for the ones adopted, after the user
   has confirmed the decision (these are changes to the language poc
   accepts, not internal choices). For each: what `Oberon2.pdf` says, what
   voc does (probed), what the other Oberon dialects do where that is
   informative (the way the `ASSERT` survey was done), the recommendation,
   and the consequences for `.sym` files, both backends and the VAX plan.
   A new switch, `-strict`, is decided here too: with it poc rejects
   everything beyond `Oberon2.pdf` (its own extensions - `HUGEINT`,
   `SYSTEM.ADDRESS`, external procedures, and whatever this step adds -
   included), which is how poc's own source can be *checked* to stay
   strict instead of relying on convention.
   - *Assignment of one `ARRAY OF CHAR` to another, and rule 6.* **Done
     2026-09-21 (inventory A21):** the survey is `doc/array-assignment-survey.md`;
     rule 6 stays as it is, voc's array rule is adopted for every element type
     (fixed array no longer than the target, or an open array; whole array
     copied by size; a longer open source is a trap, exit 9), an open array is
     never assignable (a checker/backend defect fixed), and `-strict` must
     reject the extension. `AGENTS.md` "Array assignment". What follows is the
     original plan. The three
     overlapping `000-todo.org` entries. `000-todo.org` does not say in
     which direction rule 6 ("a string constant with m characters assigns
     to an `ARRAY n OF CHAR` when m < n") is to be relaxed - exact fit
     `m = n`, or a longer string truncated - so the step begins by asking
     and by probing what voc accepts. For `fileName := name` voc's
     behavior (accepted, an extension) is the known part; what it does
     when the destination is too short (truncate like `COPY`, or trap) is
     to be probed. "Expand to any `ARRAY`" needs a use that is not
     `ARRAY OF CHAR` before it is worth the semantics of a partial copy.
   - *Declaration order.* The section order half is done (2026-09-17,
     voc-verified: `CONST`/`TYPE`/`VAR` sections may repeat and interleave,
     but every use still follows its declaration and no `TYPE`/`VAR`
     follows a `PROCEDURE`). What remains is true forward references and
     interleaving procedures with the rest. The default is to close the
     item at what voc does, since true forward references mean a
     multi-pass resolver for every declaration kind and the `PROCEDURE^`
     forward declaration already covers the case that matters. Reopen only
     for a concrete need.
   - *`SYSTEM.PTR` and the `SYSTEM` leftovers* (inventory A10 and A11, given to
     this step 2026-09-20). (1) A `PTR` cannot be dereferenced, guarded,
     `IS`-tested or used as a `WITH` variable, where voc allows some; and a
     guard followed by an index (`any(T)[i]`), or a guard to a
     pointer-to-array type, is a compile error in the backend. Decide whether
     either is wanted; the default is to keep the first (it is what makes a
     `PTR` opaque) and to close the second only when a use turns up. (2)
     `BIT`'s word-based meaning is voc's, against the report's bit of `Mem[a]`,
     and `SYSTEM.NEW` blocks are untraced by the collector: both were chosen
     with voc probed, so the proposal is to record them as decided in
     `AGENTS.md` (they are already described there) and close them.
     **Part (1) done 2026-09-21, decided with the user.** Probed voc (source and
     binary): `p^` and `NEW(p)` on a `PTR` are errors there as well (errs 57,
     111), so `AGENTS.md`'s "unlike voc" was wrong for them; a guard, `IS` or
     `WITH` on a `PTR` is accepted for a record pointer and runs, and for an
     array pointer is accepted but its C does not compile. poc keeps the `PTR`
     opaque: `EmitTagTestOnTag` reads through the block's tag word, which is
     unsound for tag 0 (`SYSTEM.NEW`) or an array descriptor, and supporting
     the record case would need a way to tell those apart. The second half was
     not `PTR`-specific: `a(ArrPtr)[1]`, `a IS ArrPtr` and `WITH a: ArrPtr` on an
     ordinary pointer to an array (the pointer's own type is the only possible
     target, arrays do not extend) all passed the checker - the report's
     "same types" reading - and then failed in the backend, `WITH` compiling
     to a branch that can never be taken (exit 6). voc rejects all three (err
     85). They are a front-end error now (`SemanticActions.IsPointerToNonRecord`,
     used by `CheckGuard`, which serves a designator guard, an argument guard
     and `WITH`, and by `IS`); nothing needs lowering. Fixture
     `semantic-reject-guard-array-pointer`.
     **Part (2) done 2026-09-21, decided with the user.** *`SYSTEM.NEW`*: kept.
     voc's `Heap.NEWBLK` tags the block `NoPtrSntl` - freed when nothing points
     at it, never scanned inside - which is poc's tag 0 (`TraceBlock` returns
     for it); recorded as decided. *`BIT`*: the docs' "voc's word test" was
     true only for `n` below 32. voc's `__BIT(x, n)` is `*(UINT64*)x >> n & 1`,
     a 64-bit read (`n` of 64 or more is a C shift too wide, the hardware
     wrapping it; probed on a buffer of eight `FF` bytes: voc `111111111`,
     poc `111100000` for `n` = 28..36), A2's is a word of address width
     rotated right by `n`, so no dialect answers `FALSE` out of range, and the
     word size differs. The VAX's `BBS`/`BBC` take a *signed* bit position
     relative to bit zero of the byte at the base address (VAX Architecture
     Handbook, 1986: the bit field "specified by ... a base address, a bit
     position" and "the bit position (P) is the signed longword specifying the
     bit displacement ... with respect to bit zero of the byte at address A").
     So `BIT(a, n)` is now that: bit `n` mod 8 of the byte at `a + n DIV 8`
     (floored), defined for every `n`, one byte read. On a little-endian
     machine it is voc's for `n` in 0..63; a big-endian target would differ
     from the word dialects (none is planned). `GenerateBit` is branch-free
     now. Fixtures `llvm-system-shifts` (shared with voc: bits 28..36, 62, 63
     of an eight-byte array) and `llvm-system-extra` (negative `n`, `n` >= 32,
     an `n` of type `HUGEINT` and `SHORTINT`; its old check of `MAX(HUGEINT)`
     as a bit number, which read a wild address under the new meaning, is
     gone).
   - *`HUGESET`.* Under `-O2` a `SET` is 32 bits and a `LONGINT` 32 bits,
     under `-OC` both 64: `SET` follows `LONGINT`. Whether a set as wide as
     `HUGEINT` on every model is wanted is answered from voc's own answer,
     `SYSTEM.SET32`/`SYSTEM.SET64` (voc's; step 7 made `SET32` an alias of
     `SET` and has no `SET64`), which if sufficient means no new predeclared name.
     If so, make them real fixed-width types the way `SYSTEM.INT8..INT64`
     became (Phase 10 step 8: `fixedBytes`, `MemoryLayout`/`LLVMTypes` sizes,
     inclusion by width, `MAX(SET32)`), rather than an alias of `SET`, which is
     32 bits under `-O2` and 64 under `-OC`; `SET32` is then 32 bits under both.
     **Done 2026-09-21, decided with the user.** The premise was wrong: voc's
     `OPM.Mod` (lines 382-385) gives `SET` 4 bytes under `-O2` *and* `-OC`
     (`doc/Features.md`'s 64 for `-OC` is not what the compiler does; probed on
     the binary too), so `SET` is 32 bits under both here (`MemoryLayout.BasicSize`,
     `LLVMTypes.BasicTypeString`; goldens `layout-size-model`, `llvm-types-dump`,
     `module-interface-*` regenerated) and `HUGESET` needs no new name: voc's own
     `SYSTEM.SET64` is adopted, a distinct 8-byte type (`Types.Set64`) with
     elements 0..63. A `SET` is included in it (zero-extended) and not the
     reverse; a mixed operation is at 64 bits. A constant set is typed by its
     value, as an integer constant is (`FoldConstantType`,
     `ConstantEvaluator.SetValueType`; the code generator folds a constant set
     expression to one immediate, `GenerateFoldedInteger`, written as an
     unsigned `u0x` hex for 64 bits so poc's own source needs no 64-bit
     `LONGINT`); a constructor with a variable element is a `SET64` only if a
     constant element is above 31 (`CheckConstantSetElement`,
     `ConstructorSetType`). Where voc is wrong poc is not: voc types a constant
     range as `SET32` and drops its high bits. `ORD` of a `SET64` is a
     `HUGEINT`. Fixtures `semantic-set64`, `llvm-set64` (both models, same
     output), `llvm-set64-import`; the folded constant sets changed
     `llvm-system-ir`'s golden. `AGENTS.md` has what a program can observe.
   - *Initializers on `VAR` declarations.* Decide the syntax and its
     reach: module variables and locals; scalars only or any type; whether
     an exported variable may carry one; how it interacts with the NIL
     default and with a read-only export; the order of evaluation among
     several; and that a `.sym` never carries it. The recommended shape is
     desugaring in the front end into assignments at the start of the
     module body or procedure, so neither backend - including the VAX one
     - changes.
   - *Record and array literals.* The largest design here. Sets already
     have `{...}`, so a literal needs a spelling that does not collide
     with it; it needs a typing rule (typed by its target or by a type
     name in front); it may or may not be a constant; and it needs a
     lowering (a temporary and a copy). Survey what other dialects do and
     decide whether the feature is worth its complexity; dropping it is a
     legitimate result.
   - *Underscores and dollar signs in identifiers.* Wanted for VMS
     (`SYS$QIOW`, `LIB$GET_VM`, `CLI$GET_VALUE`). Note the extension is
     not what makes those routines callable - `["VMS", "SYS$QIOW"]`
     already names the linkage symbol as a string - it only lets the
     Oberon-side name match. Decide whether that is worth a lexer change
     (where each character may appear, whether `$` may start a name), and
     find the consequences in advance: the `.sym` writer, LLVM symbol
     names (LLVM's unquoted identifiers already allow `$` and `_`), the
     31-character mangling of Phase 13 and Phase 15's generated definition
     modules from `STARLET.MLB`.

7. **An `Err` module.** `rtl/llvm/Err.Mod`, the counterpart of Phase 10's
   `Out`, writing to standard error: the same procedure set, the same
   buffering behavior (decide it: unbuffered is the usual expectation for
   an error stream), through the `Platform` layer written for all four
   Unix-likes. Record it in Phase 12 step 3's inventory as a module poc
   supplies that voc does not. **Testing**: a fixture that writes to both
   streams and checks each goes to its own file descriptor.

8. **Nested procedures.** Lower them in the LLVM backend; the full plan, with
   the design decisions and their reasons, is `doc/nested-procedures.md`. In
   short: they are only ever called by name (`Oberon2.pdf` 6.5 forbids one as a
   procedure value, and the checker enforces it), so none outlives its enclosing
   activation, and **lambda lifting by reference** is enough - each nested
   procedure becomes an ordinary function that takes, as hidden trailing
   parameters, the addresses of the enclosing variables it needs, bound in
   `cg.locals` under the same objects so no designator codegen changes. What a
   procedure needs is a fixed point over the nested call graph (its own uses,
   what its nested procedures need, what the nested procedures it calls need),
   ordered deterministically so the IR is byte-stable for the fixed point, and
   found by *exact* name resolution against the real scope chain (decided
   2026-09-20), not by matching spellings as the `WITH` safety check does: a
   false match there only rejects too much, here it would pair a call with a
   binding that does not exist; a long list of hidden parameters is accepted
   until measured (decided 2026-09-20), the fallback being one pointer to a
   frame record. The
   analysis is a new backend-independent module `NestedProcedures.Mod`
   (`src/front/`, which the VAX backend will reuse) with a `poc -dump-nested`
   mode, so it is golden-tested before any code generation exists. Steps, each
   with fixtures that fail first and a green `make check`: (0) groundwork with
   no behaviour change (`SemanticActions.DeclareLocalProcedures`, a body scope
   passed in rather than opened); (1) the analysis and `-dump-nested`; (2)
   nested procedures that need nothing; (3) hidden parameters for scalars and
   aggregates; (4) `VAR`, `VAR` record (tag), open-array (lengths) and receiver
   variables, and `WITH`; (5) depth, siblings, mutual recursion through a
   forward declaration, recursion of the enclosing procedure; (6) remove the
   error, `AGENTS.md`, both BSD hosts, both word sizes. **Exit gate**: the
   fixtures of the plan's section 6 pass under both compilers, both size
   models, at both word sizes, on Linux, NetBSD amd64 and OpenBSD i386; the
   program that `llvm-reject-nested-procedure` used to reject prints `ok` (it
   is in `llvm-nested-uplevel`); the fixed point still exact; no nested-procedure
   error left in the backend.
   *Progress (2026-09-20):* steps 0 to 5 are done: nested procedures are lowered
   in full (hidden trailing address parameters, with a tag or lengths where the
   variable is a `VAR` record or an open array; step 3 did steps 4 and 5's
   mechanism too), the error is gone, and the fixtures `llvm-nested-basic`,
   `-features`, `-uplevel`, `-params`, `-deep`, `-gc`, `-import` and `-ir` pass
   (the runtime ones also as i686 executables). Step 1 added `NestedProcedures.Mod`
   (also built by `tools/bootstrap/stage0`), `poc -dump-nested`, and six
   `nested-analysis-*` fixtures; poc's own source, which has no nested
   procedure, gives an empty analysis for every file. Left: step 6, `AGENTS.md`
   and the BSD hosts; see `doc/nested-procedures.md` section 5.

9. **Close-out.** `000-todo.org` is brought up to date entry by entry
   (each item `DONE` with a one-line account, or `DROPPED` with the reason;
   the Phase 12 entries left open and marked as such); the "Open design
   questions" section keeps only resolved records, each stating what was
   decided; `AGENTS.md` gets the decisions that change what a poc user
   sees (the same way it records HUGEINT, procedure values and the rest);
   and the BSD runs skipped while the hosts were unreachable are made up:
   the whole conformance suite, at both word sizes, on Linux and at least
   one BSD. **Exit gate**: `make test` clean at both word sizes; the
   Stage 1/Stage 2 fixed point of Phase 10 re-run against the changed
   front end and back end and still exact; every table row above with a
   verdict; and no unlabeled "undecided" left anywhere in `PLAN.md`,
   `AGENTS.md` or `000-todo.org`.

**Testing summary**: each decision comes with the voc probe that supports
it, recorded where the decision is; each implemented item has a fixture
that fails before the change and passes after; the step 4 measurement and
the step 5 debugger sessions are fixtures too; step 9's whole-suite run
and the bootstrap fixed point are the gate.

### Phase 12 — Detailed library/module support (voc's options, static/dynamic libraries, voc's module inventory)

**Goal**: decide, from primary sources and not from memory, what poc must
offer *beyond* what Phases 9-10 already give it - the command-line
surface a voc user expects, a way to build the libraries a program links
against, and which of the libraries and modules voc supplies are worth
having - and then build what the decisions call for. Phase 10 covers
exactly what poc's own source needs plus the Oakwood basic modules and
`SYSTEM`; this phase is everything else, and it starts as investigation:
steps 1-3 produce written inventories and decisions (recorded here and in
`AGENTS.md`), and only steps 4-6 write code. Placed before the VAX/VMS
backend (Phase 13) because the library question is an LLVM/Unix one and
nothing in the VAX work depends on it.

**Explicit non-goals**: the VAX/VMS backend, which needs its own answer to
"what is a library" (VMS shareable images, object libraries) and is not
decided here; and the self-hosting bootstrap itself, which is Phase 10's
own exit gate - this phase may assume it has been reached, or not, as
convenient, but must not be a prerequisite of it.

1. **Which of voc's command-line options poc needs.** Go through every
   option `voc` accepts and decide, for each, whether poc implements it,
   implements it differently, or does not. The sources are the option
   list `voc` itself prints with no arguments, `doc/Compiling.md` and
   `doc/Features.md` in the clone under `/usr/local/sw/src/lang/Oberon/
   vishap/compiler`, and - since the printed list may be incomplete -
   `OPM.Mod`'s own option parsing (the source of truth: probe anything it
   accepts that the usage text does not mention). As of voc 2.1.0 the
   printed groups are: run-time safety (`-p` NIL-initialize pointers, `-a`
   halt on assertion failure, `-r` range checks, `-t` type-guard halt,
   `-x` index-range halt); symbol-file management (`-e`, `-s`, `-F`);
   C-compiler and linker control (`-m`/`-M` main module linked
   dynamically/statically, `-S` do not call the C compiler, `-c` do not
   link); miscellaneous (`-f` no VT100 control characters, `-V`
   debugging messages); the size model (`-O2`, `-OC`, and `-OV`, which poc
   does not have); and target address size and alignment (`-A44`,
   `-A48`, `-A88`). poc already has `-O2`/`-OC`, `-target <triple>`,
   `-build`, `-o`, `-emit-llvm-ir`, `-emit-interface`, `-import-path`,
   `-output-dir`. Questions the triage must answer with evidence rather
   than assume: which safety checks poc emits unconditionally today (NIL,
   index, type guard, `WITH`, `CASE`, array length) and which of them
   voc's switches would let a user turn off or on (`-r` range checking
   has no poc counterpart at all). **`-A44`/`-A48`/`-A88` answered
   (2026-09-20, `000-todo.org`): not applicable, and poc needs no
   counterpart.** voc's `-A` exists because it generates portable C and
   has no other way to tell the *downstream* C compiler's ABI (address
   size and struct alignment are genuinely independent there - `-A48`,
   32-bit addresses with 64-bit alignment, is a real 32-bit-Windows/ARM
   quirk); poc emits an explicit LLVM `target datalayout` string per
   `-target` triple (`LLVMCodeGenerator.dataLayoutW64`/`dataLayoutW32`,
   verified against real hardware, Phase 8 step 13) that already pins
   down both axes together - choosing the triple chooses both at once,
   with nothing downstream left to infer them independently. What
   `-e`/`-s`/`-F` mean for a `.sym` poc always regenerates whole-program
   (Phase 9 step 4a); how `-m`/`-M`/`-S`/`-c` map onto `-build`,
   `-emit-llvm-ir` and step 2's library modes; and whether `-OV` is worth a
   third size model. The result is a table - option, voc meaning, poc
   decision (adopt as-is / adopt with a different meaning / not
   applicable / deferred), reason - kept in `PLAN.md` (or a file it names),
   plus the flags it adopts, each implemented in `Poc.Mod` with a fixture
   and cross-checked against real voc where voc's behavior is
   observable. **Testing**: a golden `-help`/usage fixture, and a fixture
   per adopted flag that would otherwise be untested.

2. **Building static and dynamic libraries with poc.** Decide how a
   program compiled by poc links against libraries poc itself built, and
   build it. voc's answer is the reference (`libvoc-O2.a`/`.so` and
   `libvoc-OC.a`/`.so` in its install `lib` directory - one library per
   size model, since its `.sym` files carry computed sizes and offsets);
   poc's differs at the root, since a `.sym` is target-independent source
   (Phase 7, Phase 9 step 4a) but the object code is not - it is specific
   to word size, size model and target triple, so a library's identity
   is that whole tuple and the layout of its output directory has to say
   so. Questions to settle: what the unit of a library is (a set of
   modules with their `.sym` files, found through `-import-path`); the
   command-line shape (a "compile these modules into a library" mode and
   the "link against it" flags, informed by step 1's triage of `-m`/`-M`/
   `-c`); a static library as an `ar` archive of per-module objects
   (`clang -c`, then `ar`) and a dynamic one as `clang -shared` over
   position-independent objects - on Linux, NetBSD, OpenBSD and FreeBSD,
   which differ in the details (runtime search path, `-rpath`, symbol
   versioning) more than they will look like they do; exported-symbol
   visibility, given that every Oberon procedure is `@Module.Proc`; what
   module initialization and `ModuleTable`'s root registry do when the
   modules are in a library, including in a shared one loaded by more than
   one program (Phase 9 step 4's per-module GC root tables); where the
   collector and the rest of `rtl/llvm` live (in every library that needs
   it? in one library of their own? - two copies of the collector in one
   process would each be blind to the other's heap); how the `main`
   generated for a program finds the initializers of every module it
   links, library or not; and record-layout and `ProcTab` stability
   across a library rebuild, since Phase 9 step 4a's importer reproduces a
   base type's layout from the `.sym`. The deliverable is the design,
   written into `PLAN.md`, then the implementation: `poc` builds `rtl/llvm`
   itself as a library and a program links against it both ways.
   **Testing**: build a small library of two or three modules with
   dependencies between them; link a program against it statically and
   dynamically; run both, at both word sizes, on Linux and on the BSD
   hosts (the same real-hardware access as Phase 9 step 9); and the
   negative cases - a `.sym` that does not match the library it names, a
   missing library - fail with a message and not a crash.

3. **A complete inventory of the libraries and modules voc supplies.**
   From the sources, not from memory: enumerate every module under the
   voc clone's `src/runtime` (`SYSTEM`, `Heap`, `Files`, `In`, `Out`,
   `Math`, `MathL`, `Modules`, `Oberon`, `Platformunix`/`Platformwindows`,
   `Reals`, `Strings`, `Texts`, `VT100`, as of this writing), every
   library directory under `src/library` (`misc`, `ooc`, `ooc2`,
   `oocX11`, `pow`, `s3`, `ulm`, `v4`), the modules the install actually
   ships (`showdef` on the installed symbol files under
   `/usr/local/sw/versions/voc/git/{2,C}/sym`, which also shows what each
   one exports), and the programs under `src/tools` (`autobuild`,
   `beautifier`, `browser`, `coco`, `HeapDump`, `make`, `ocat`,
   `testcoordinator`, `vmake` - to be classified as library, program, or
   neither). For each module record: name and the directory it lives in;
   what it is for; its imports (so the dependency graph, and so which
   modules can be taken without dragging in others); whether it depends on
   the platform (`Platformunix`, `oocwrapperlibc`, `oocFilesHost`,
   `oocProgramArgsHost`), on the C library, on X11, on zlib, or on the
   size model; whether it is part of a standard (Oakwood, the ooc library
   family) or voc's own; whether it is already in Phase 10's scope; and
   its licence, since poc cannot ship what it cannot legally ship. The
   result is a table kept as a file the plan names, not prose - the
   *complete* list the plan has been missing, with `ulm` and `v4`
   (not yet looked at at all) filled in like the rest.

4. **Deciding what poc supports.** Using step 3's table, sort every
   module into: already covered by Phase 10; wanted, with a priority;
   deferred; or not wanted, with the reason. Criteria: how useful it is to
   a program written against voc (the existing Oberon-2 corpus poc should
   be able to compile); whether it can be written portably to all four
   Unix-likes (no Linux-only syscalls, no library the BSDs lack); whether
   it needs an external C library poc would then have to link
   (zlib for `ethGZReaders`/`ethZip`, X11 for `oocX11`/`oocXYplane`); how
   much of the module is really the host Oberon *system* (`Oberon`, `Texts`
   rely on it) and so would need a substitute; and the cost. Record the
   decisions, and the ones deliberately left open, in `PLAN.md`'s open
   design questions and `AGENTS.md`.

5. **Implementing the modules chosen.** Write each as ordinary Oberon-2
   compiled by poc, into step 2's library, in the order dependencies and
   step 4's priorities give; the exact list is step 4's output, and this
   step is updated with it rather than guessed at now. Platform-dependent
   ones get an OS layer written with all four Unix-likes in mind (the
   standing portability rule for `rtl/llvm`), not Linux-only libc
   behavior. **Testing**: per module, compile+link+run+diff fixtures
   cross-checked against the same module under real voc wherever both
   exist, the way Phase 9's fixtures were; behavior that differs from voc
   on purpose is documented where it differs.

6. **Exit gate.** Every module step 4 selected builds into both the
   static and the dynamic library and passes its fixtures, at both word
   sizes, on Linux and at least one BSD, with `make test` clean on every
   combination - the same bar as Phase 9 step 9.

**Testing summary**: steps 1-4 are decisions with written artifacts
(tables and a design), verified against the primary sources they cite;
steps 2 and 5 are compile+link+run+diff fixtures; step 6 is the
whole-matrix gate.

### Phase 13 — VAX/VMS MACRO-32 backend (scoped, deferred, non-executable)
`VaxTypes.Mod`, `VaxCodeGenerator.Mod`, `VaxToolchainDriver.Mod` (stub
only — no assemble/link/run, per the locked-in decision).
**Explicit scope bound** (to prevent drift): targets exactly Phase 8's
narrow vertical-slice feature set (straight-line code, IF/WHILE/CASE,
arrays/records) — *not* full GC/dispatch parity. "Done" means
hand-reviewed `.mar` output checked into
`test/conformance/*/expected-vax.mar`-style fixtures with a reviewer
rationale comment, not an automated pass/fail. Assembling, linking and
running the output - under SIMH-hosted VMS 5.5-2, or real hardware - is
Phase 14's, which also lifts the vertical-slice bound above.

**Symbol-name mangling is required, not optional**: VAX MACRO-32 symbols
are limited to **31 characters**. This project's own naming convention
favors longer, descriptive Oberon-2 identifiers (module names, exported
procedure names, qualified `Module.Procedure` forms, type-bound-procedure
dispatch names), which will routinely exceed that limit — unlike the LLVM
backend, which has no such restriction and can emit names close to
verbatim. `VaxTypes.Mod`/`VaxCodeGenerator.Mod` must therefore implement a
deterministic name-mangling scheme (e.g. truncate-plus-hash-suffix) for
every emitted MACRO-32 symbol, and this scheme needs its own fixtures
(long/colliding names deliberately included in the Phase 13 test set) to
confirm two distinct Oberon-2 names never mangle to the same 31-character
symbol.

**External procedures under the VMS Calling Standard**: any procedure
declared external (Phase 6's FFI extension) must be lowered according to
VMS's own well-defined Calling Standard, not poc's internal calling
convention for ordinary Oberon-2 procedures — this is separate work from,
and in addition to, plain MACRO-32 codegen for pure-Oberon code, and its
external-symbol names are subject to the same 31-character limit above.

### Phase 14 — Running on VAX/VMS: assemble, link, run, and bootstrap poc there

**Goal**: the MACRO-32 Phase 13 writes is assembled, linked and run on
VAX/VMS 5.5-2 (a SIMH-hosted VAX, or real hardware), with just enough
runtime to compile poc itself, and poc - built for VAX/VMS - then compiles
its own source *on* VAX/VMS: the VMS counterpart of Phase 10's
self-hosting. This lifts two limits of earlier phases, which no longer
apply once it starts: the locked-in "assembling/linking/running is out of
scope" (Phase 13 stays what it was - hand-reviewed and non-executable -
and this phase is what runs it), and Phase 13's own scope bound to Phase
8's vertical slice, since poc's source uses far more than that.

**Explicit non-goals**: libraries beyond what poc's own source needs
(Phase 15); any VMS other than VAX 5.5-2 - no Alpha, Itanium, or later VAX
release, though nothing should be gratuitously specific to the exact
release; DECnet, DECwindows, layered products. Phase 15 owns shareable
images and the native VMS libraries; this phase links objects and, at
most, object libraries.

1. **A working VAX/VMS environment and a way to drive it.** Settle what
   runs: which SIMH VAX model VMS 5.5-2 boots on, and where the installation
   media and licences come from (a hobbyist licence - recorded, not assumed).
   Confirm on the guest what the base kit provides (`MACRO`, `LINK`,
   `LIBRARY`, `DCL`, the RTLs) and which layered tools poc must not depend
   on. Decide how files cross between the Linux/BSD host and the guest -
   virtual disk image, tape image, `kermit`, `ftp`, a shared mount - and
   how a test is driven and its output captured (a serial or telnet
   console script). Automate that as one host-side command that copies
   sources in, runs a `.COM` procedure, and copies results out, since
   every later step's fixtures depend on it. Recorded in the plan, with
   the choices that were rejected.

2. **Assemble, link and run hand-written, then generated, code.** Before
   any generated code: a hand-written MACRO-32 "hello" through
   `MACRO`, `LINK` and `RUN`, proving the loop end to end. Then every
   `expected-vax.mar` fixture Phase 13 checked in is assembled and run,
   turning "hand-reviewed" into automated pass/fail wherever the fixture
   is runnable; whatever the assembler rejects is a Phase 13 bug and is
   fixed there. `VaxToolchainDriver.Mod` stops being a stub: it emits the
   `.mar`, drives `MACRO`/`LINK` (locally on the guest, or by the step 1
   command from the host).

3. **Widening the backend to what poc's own source uses.** Survey poc's
   own source (`src/`) for every construct it needs - pointers and `NEW`,
   records and extension, type-bound procedures, `WITH`/`IS`, open
   arrays, sets, `REAL`/`LONGREAL`, procedure values and procedure-typed
   parameters, strings and `CHAR` arrays, `CASE`, external procedures - and
   bring `VaxCodeGenerator.Mod` to parity with the LLVM backend for
   those, in dependency order, each with a run-and-diff fixture that is
   also a Phase 9 fixture (the same `.mod`, same expected output, on both
   backends; a fixture that only one passes is a bug). Three things need
   real design, not just porting: (a) **floating point** - VAX
   `REAL`/`LONGREAL` are F_floating and D_floating (or G), not IEEE 754, so
   constant emission, `ConstantEvaluator`'s folding, `MAX`/`MIN` of the
   real types, `ParseReal`/`FormatReal` and the `.sym` round trip, and the
   hardware conversions all change; decide the `LONGREAL` format
   (D or G) from what VMS's own compilers and RTLs default to; (b)
   **calling convention** - internal Oberon procedures versus the VMS
   Calling Standard (`CALLS`/`CALLG`, argument lists, register save masks,
   condition values); Phase 13 says external procedures use the standard
   and ordinary ones poc's own, and this step decides whether the
   hidden tag/length arguments and procedure values keep working that way
   or whether one convention for everything is simpler (Phase 15's AST
   support pulls toward the latter); (c) **traps** - index, NIL,
   type-guard and length failures become VMS conditions or a status exit,
   and what a poc program's exit status looks like to DCL.

4. **A minimal VAX runtime, `rtl/vax`.** Only what poc itself needs, as
   ordinary Oberon-2 over a thin MACRO-32/RTL layer wherever possible:
   program start and command-line access; memory from the system
   (`LIB$GET_VM`/`SYS$EXPREG`, to be confirmed); the collector,
   ported (its roots are the machine stack - which grows down on the VAX,
   with the callee-saved registers R2-R11 to be captured - and the
   per-module root tables; the mark phase needs the same type
   descriptors as on LLVM); file I/O for `Files` over RMS (poc reads
   source and writes `.mar`, `.sym` and `.ll`; RMS record files, not
   byte streams, so the choice of record format and how a `Rider` reads it
   is a design point, and the text files must round-trip exactly);
   `Platform` (environment as logical names or symbols, current directory,
   `Chdir`, process id, delete); `Out`. VMS-specific problems the LLVM
   runtime never met, each to be settled here: ODS-2 file names
   (uppercased, 39.39, with `;version`) against the module-name-to-file-name
   mapping `Files.Old(moduleName + ".sym")` assumes, and against
   Oberon module names longer than what fits or differing only in case;
   the directory syntax (`dev:[dir.sub]file.type`) against `-import-path`,
   `-output-dir` and `POC_IMPORT_PATH`, whose separator is the colon VMS
   uses inside device names (logical names and search lists are the
   natural replacement); and the command line, which DCL upcases and
   splits before a program sees it, against `poc -build -o x file.mod`
   (a foreign command with quoted arguments, or a CLD-defined verb -
   decide, and say which).

5. **Test harness on VMS.** `make test` gains a VAX target: the
   conformance fixtures poc can run there are copied to the guest, built
   with `MACRO`/`LINK`, run, and their output diffed with the same
   `expected` files; `MMS` (the DEC Module Management System - its manual
   is among the local reference material) or a `.COM` procedure is the
   guest-side build driver, whichever step 1 chose. Fixtures that cannot
   pass on VAX for a good reason (IEEE-specific constants) get a
   VAX-specific `expected` file rather than being skipped silently.

6. **Bootstrap on VAX/VMS.** poc for VAX/VMS is built in stages. **V1**:
   the host's `poc` cross-compiles poc's own source to `.mar`; assembled
   and linked on the guest, it is a VAX `poc.exe`. **V2**: that `poc.exe`,
   run *on VMS*, compiles poc's own source to `.mar`, which must be
   byte-identical to V1's (modulo paths and version numbers) - the
   fixed-point test, a text diff of the two `.mar` sets. **V3**: the
   `poc.exe` assembled from V2's `.mar` compiles the source again, again
   identical. The whole conformance suite then passes under the V2/V3
   compiler. `tools/bootstrap` gains the corresponding scripts.

**Testing summary**: step 2's fixtures and step 3's shared fixtures
are compile+assemble+link+run+diff on the guest; step 6's fixed point is
the phase's exit gate, the way Stage 1/Stage 2 was Phase 10's.

### Phase 15 — Detailed library/module support for VAX/VMS

**Goal**: for VAX/VMS, what Phase 12 did for the LLVM targets - libraries
poc can build and programs can link against, a decision about which
existing Oberon modules to support - and then what only VMS has: its own
native libraries, and asynchronous system traps. It is the same
investigation-first shape as Phase 12: steps 1, 2 and 4 write down
inventories and decisions from primary sources (the VMS and VAX manuals
kept locally under `~/Reference/Computer/OS/VMS` and `.../Systems/VAX`
- among them the VAX MACRO reference, the VMS system software and
programming-environment manuals, the RMS and VAX C RTL manuals, and the
DEC MMS guide) before steps 3, 5 and 6 build anything.

**Explicit non-goals**: the LLVM targets (Phase 12); VMS versions and
architectures other than VAX 5.5-2; layered products (DECwindows, DEC
C++, and so on) unless step 4 chooses one deliberately.

1. **Static and dynamic libraries on VMS.** Work out how poc builds them
   and how a program links against them - this is the first thing, because
   step 3 and step 5 both put modules in libraries. The VMS analogues,
   to be confirmed against the manuals and then tried: an **object library**
   (`LIBRARY/CREATE`, `.OLB`, with `LINK prog, lib/LIBRARY` pulling in only
   the modules that resolve undefined symbols) for the static case;
   a **shareable image** (`LINK/SHAREABLE`, activated at run time, installed
   with `INSTALL` where a system-wide one is wanted) for the dynamic case.
   Questions that are specific to the VAX: shareable-image code must be
   position independent, so `VaxCodeGenerator.Mod` must emit PC-relative
   references and the right program-section attributes (`PIC`, `SHR`,
   `NOSHR`, `WRT`) for code, constants and per-process data - which may
   change code Phase 14 already emits; how a shareable image exports
   its entry points (transfer vectors, universal symbols, or the linker's
   symbol-vector option, whichever 5.5-2 has), and how a *version* is
   expressed (`GSMATCH` and major/minor identification) so that the layout
   guarantee `.sym` files give importers holds across a rebuild; the same
   31-character symbol limit and Phase 13's mangling, which must now be
   stable across separately built libraries (a hash suffix must not depend
   on what else was in the compilation); where the collector and module
   registry live when there is more than one image, and what happens to
   writable data (it is per-process, and a shareable image gets its own
   copy of it); and how `.sym` files are found, through logical names or
   search lists rather than a Unix path. The build descriptions are MMS
   ones. **Testing**: a small library of a few dependent modules built
   both ways; a program linked against each and run; the failure cases
   (a `.sym` that does not match its image, a missing image, a version
   mismatch) reporting a message rather than crashing.

2. **Which existing Oberon libraries and modules to support on VMS.**
   Take Phase 12's complete inventory of voc's modules and Phase 10's
   Oakwood set, and sort each for VAX/VMS: portable as they are; needing a
   VMS platform layer (`Platform`, `Files`, `Modules` - the ones written
   with the four Unix-likes in mind now need a fifth answer); depending on
   IEEE 754 (`Reals`, `MathL`, anything that takes a real apart into
   bits or assumes 64-bit doubles - VAX floating point is different, see
   Phase 14 step 3); depending on the C library, zlib or X11, none of which
   VMS 5.5-2 has by default; or hostile to ODS-2 file names. The output is
   a table of module and verdict, kept as a file the plan names, and the
   decisions.

3. **Implementing the chosen Oberon modules on VMS**, into step 1's
   libraries, in dependency order, each with fixtures shared with the LLVM
   side where the module is the same (the same `.mod` and `expected`, run
   on both), and VAX-specific fixtures where the behavior differs on
   purpose, documented where it differs.

4. **Which native VAX/VMS libraries to support.** From the manuals, not
   memory, list what a VMS programmer expects to reach: the run-time
   library families (`LIB$` general utilities, `STR$` strings, `MTH$` and
   `OTS$` math and language support, `SMG$` screen management, `CLI$` and
   `LIB$GET_FOREIGN` for the command line); the system services (`SYS$`:
   `$QIO`, `$ASSIGN`, timers, mailboxes, locks, process and device
   information, logical names, and the rest); RMS, the record management
   services (`FAB`, `RAB`, and the `$OPEN`/`$GET`/`$PUT` family); and
   condition handling (`LIB$SIGNAL`, `LIB$STOP`, condition handlers,
   exit handlers). For each: what it is for, whether it is worth an Oberon
   interface, and what it costs. Record the choices, and what is left
   out and why.

5. **Calling native libraries from Oberon.** The external-procedure
   declaration (`PROCEDURE ["VMS", ...]`, already accepted, recording only
   a convention and a linkage name) is not enough for VMS, and what more
   it needs is decided here. VMS routines take their arguments by
   *reference*, by *value*, or by *descriptor* (a string's class and
   length and address travel together), and return a condition value in
   `R0`; the declaration must say which mechanism each parameter uses, and
   the language needs a way to hold a string descriptor and an item list.
   The system's own definitions - the `$SSDEF` status codes, `$IODEF` function codes, RMS's control-block
   fields, item-list layouts - live in macro libraries (`STARLET.MLB`);
   decide whether a tool generates Oberon `CONST`/`RECORD` definition
   modules from them or they are written by hand, and how the generated
   modules track the kit they came from. Implement it, and write the
   interface modules step 4 chose, each with a fixture that calls the real
   service on the guest and checks a result.

6. **Asynchronous system traps and other asynchrony.** VMS systems
   programming leans on them: a service such as `$QIO`, `$SETIMR` or `$ENQ`
   is asked to *complete* asynchronously and to call a routine (an AST)
   when it does, at any point in the program, on the program's own stack,
   with `$SETAST` to enable or disable delivery and `$DCLAST` to queue one.
   What that demands of poc is the point of the step, and it has to be
   worked out and not guessed: (a) an AST routine is an Oberon procedure
   called *by VMS*, with an argument the program chose, so a procedure
   value (Phase 9 step 8) must be callable under the VMS Calling Standard -
   the strongest argument for one calling convention throughout (Phase 14
   step 3b), or else for a declared "AST routine" procedure kind with an
   adapter; (b) the **collector** may be interrupted by an AST that
   allocates or that touches the heap, and an AST frame sits on the stack
   the collector scans, so allocation and collection either run with
   delivery disabled or are proven safe against it - this is the hardest
   part and must be designed before any is written; (c) module
   initialization, `NEW`, and any runtime state that is not reentrant;
   (d) the language-level primitives a program needs to share data with an
   AST safely - interlocked queue and bit-set instructions, event flags
   (`$SETEF`, `$WAITFR`, `$SYNCH`), and whether `SYSTEM` grows an
   AST-safe operation set; (e) condition handlers, exit handlers
   (`$DCLEXH`) and the runtime's own traps (Phase 14 step 3c), which are
   asynchronous in the same sense. The result is a design written into
   this plan, an Oberon-level `VMS` module (or modules) that exposes it
   ($QIO with a completion AST, timers, mailboxes, event flags, condition
   handlers), and fixtures on the guest that fire ASTs while the main
   program allocates heavily - so that the collector's interaction with
   them is tested where it would fail - and that fail if the AST
   delivery rules are wrong.

7. **Exit gate.** Every module and interface chosen builds into both
   library kinds and passes its fixtures on the guest, the AST fixtures
   pass repeatedly (asynchrony makes a single pass weak evidence), and the
   whole VAX conformance suite from Phase 14 is still clean.

**Testing summary**: steps 1, 3, 5 and 6 are fixtures run on the guest;
steps 2 and 4 are decisions with written artifacts, verified against the
manuals they cite; step 7 is the gate.

### Phase 16 — Direct VAX/VMS object files (no MACRO-32 in the loop)

**Goal**: `poc` writes VAX/VMS object modules (`.OBJ`) itself, so a
compile is Oberon source to object file and `LINK` is the only VMS tool
left in the build - the assembler (`MACRO`) drops out. Phases 13-15 emit
MACRO-32 text and hand it to the assembler; that stays as `-emit-mar`, the
human-readable form the earlier phases reviewed and a debugging aid (and
the oracle this phase tests against), but it stops being the path a normal
build takes. Reasons to do it, to be checked and not assumed: the
assembler is one less tool that has to be present and fast on the guest
(Phase 14 step 1 confirms from the 5.5-2 SPD what the base kit contains);
a compile that produces its object directly does one pass over the code
instead of two; and poc controls exactly what goes into the object, the
debug and traceback information included.

**Explicit non-goals**: writing executable *images* (`LINK` stays - it
also builds shareable images, applies the option file, and is what
Phase 15's libraries rely on); writing object *libraries* (`LIBRARY`
stays); any object format other than VAX/VMS's (no ELF, no COFF), and any
VMS release but 5.5-2; a MACRO-compatible assembler for hand-written
MACRO-32 - only the subset poc itself emits has to be encoded.

1. **The object language, from the 5.5-2 documentation.** The VAX/VMS
   object module is a sequence of variable-length records of a few kinds -
   the module header (`HDR`), the global symbol directory (`GSD`: program
   sections, global symbol definitions and references, entry points), the
   text-information-and-relocation records (`TIR`: the code and data
   bytes, and relocation expressed as a small stack language), debug and
   traceback records (`DBG`/`TBT`), and the end of module (`EOM`) - as the
   linker and the object-language documentation describe them, all to be
   confirmed against the manuals for this release (`vax-vms-manuals-to-get.md`
   lists what is still to be found, the object-language reference among
   it). Write a specification, in this plan or a file it names, of exactly
   the subset poc needs: each record kind and field, the program-section
   attributes it uses, how a global symbol and an entry point with its
   register-save mask are expressed, how relocation against another
   module's symbol or a program-section base is written, the limits (the
   31-character symbol length again - Phase 13's mangling is unchanged),
   and the on-disk form (an object file is a record-oriented RMS file, so a
   file merely copied from another system's byte stream is *not* an object
   the linker accepts until its record attributes are set; `FDL` and
   `CONVERT` are the guest-side tools, and `Files` on VMS (Phase 14 step 4)
   is what lets poc write records directly). Read real objects first: what
   `MACRO` produces for each of the Phase 13 fixtures, dumped with
   `ANALYZE/OBJECT` and in hex, is the ground truth the specification is
   checked against.

2. **An instruction-level representation under the code generator.**
   `VaxCodeGenerator.Mod` today writes MACRO-32 text as it walks the tree.
   To write bytes the same decisions must be available as data: a
   `VaxInstruction` representation (opcode, operand specifiers with
   addressing mode, register, displacement and symbol, labels, directives)
   built once, and two consumers of it - the existing text printer, which
   must produce exactly the `.mar` the Phase 13 fixtures already hold, and
   the new encoder. The refactor is done first and on its own, with the
   `expected-vax.mar` fixtures (and the runnable Phase 14 ones) as the
   safety net: nothing about the emitted assembly may change. The subset of
   MACRO-32 poc's generator uses is written down here, since it is what
   the encoder must cover and not a line more.

3. **The instruction encoder.** VAX instructions are an opcode (one or
   two bytes) followed by operand specifiers, each a mode nibble and a
   register with any immediate, displacement or index bytes after it;
   branches and `JMP`/`JSB` targets are the difficulty, because the
   displacement size (byte, word, longword) depends on the distance and
   the distance depends on the sizes chosen - the assembler's job that poc
   now does itself: label and program-section layout, branch-displacement
   selection with relaxation to a fixpoint, PC-relative references,
   `.ENTRY` masks, and the data directives the generator emits (`.LONG`,
   `.WORD`, `.BYTE`, `.ASCIC`/`.ASCII`, `.BLKx`, `.ALIGN`, floating
   constants in the format Phase 14 step 3 chose). **Testing**: byte-for-
   byte comparison of the encoded text of every fixture module against the
   text `MACRO` produces from the same `.mar` on the guest - not merely
   "the linked program runs", since a wrong encoding that happens to run is
   the failure this step exists to catch - with the differences that are
   legitimate (an assembler's choice between equivalent encodings) listed
   and explained, not waved through.

4. **The object writer, `VaxObjectWriter.Mod`.** From the encoded
   program sections write the records step 1 specified: the header, one
   `GSD` entry per program section and global symbol, the code and data as
   `TIR` with relocation for every symbolic reference the encoder could not
   resolve within the module (calls to other modules' procedures, the
   type-descriptor and string-constant symbols, external `["VMS"]`
   routines), and the end record. Phase 15's requirements ride on it:
   position-independent code and the program-section attributes a shareable
   image needs, universal (exported) symbols, and entry points a transfer
   vector can name. **Testing**: `ANALYZE/OBJECT` on poc's output and
   on `MACRO`'s for the same source, compared; and the decisive test, `LINK`
   accepts it and the program runs.

5. **Debug and traceback information.** Decide how much: at least the
   traceback records (`TBT`) that let an unhandled condition print a
   routine-and-line traceback, since a poc program that traps otherwise dies
   with no context; and, if worth it, debug symbol records so `DEBUG` can
   show Oberon source lines and variables - which needs the source-position
   information the front end already carries (every node has a line and
   column) threaded down to the encoder, and Oberon type descriptions in
   the debugger's terms. Decided here from what the 5.5-2 debugger can
   consume, and recorded, including what is left out.

6. **Wiring it in.** A new mode (`-emit-obj`, and the default on VMS,
   with `-emit-mar` keeping the Phase 13 behavior) writes `<module>.OBJ`;
   `VaxToolchainDriver.Mod` stops invoking `MACRO`. Every earlier phase's
   VAX fixtures run in both modes - built through `.mar` and `MACRO`, and
   built directly - and give the same output; Phase 15's object libraries
   (`LIBRARY/CREATE` of poc's `.OBJ` files) and shareable images
   (`LINK/SHAREABLE`) work with the direct objects unchanged, and are tested
   that way.

7. **Bootstrap again, and the exit gate.** Rebuild poc for VAX/VMS with
   the direct writer, on the guest: the V1/V2/V3 fixed point of Phase 14
   step 6, now over `.OBJ` files - an object compiled by the poc built from
   the previous stage must be byte-identical to the one the stage before
   produced from the same source (modulo the module header's timestamp
   and the file's creation attributes, which the specification lists). The
   whole VAX conformance suite passes with objects written directly, and
   the whole Phase 15 suite, ASTs included; the run that builds poc must
   involve no `MACRO`.

**Testing summary**: steps 2 and 3 are byte-level comparisons against the
existing text path and against the assembler; steps 4 and 6 are
`ANALYZE/OBJECT` comparisons plus link-and-run; step 7's fixed point
over object files is the gate.

## Open design questions

None is open now (2026-09-25).

Decided, with the full reasoning in `doc/design-decisions.md` under the
same names:

- No `ASSERT` (decided 2026-09-25: `doc/assert-survey.md`)
- Open array dimension limit
- External procedure declaration syntax
- `-OC`-equivalent elementary-type-size model
- Type guards in designators — two separate gaps
- Predeclared "functions" in constant expressions — really two separate gaps, not one
- Constant arithmetic doesn't re-derive its result's minimal type from the computed value
- Declaration order: voc relaxes CONST/TYPE/VAR *section* order, never reference order

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
- **Phase 10 self-hosting**: Stage 1 vs. Stage 2 output diff as the
  fixed-point proof; full conformance suite must pass under Stage 1 before
  voc is retired from the day-to-day build loop.
- **Phase 11**: every open design question and `000-todo.org` item with a verdict, `make test` clean at both word sizes on Linux and a BSD, and the Stage 1/Stage 2 fixed point still exact after the front-end and backend changes.
- **Phase 12**: the option triage, library design and module inventory
  written down and verified against voc's own sources; then the whole-
  matrix gate (both library kinds, both word sizes, Linux and a BSD).
- **Phase 13**: manual review only (no automated run), explicitly bounded
  in scope as described above.
- **Phase 14**: fixtures run on a real or SIMH-hosted VAX/VMS 5.5-2
  guest; exit gate is the bootstrap fixed point there (V1's `.mar` for
  poc's own source identical to what poc itself produces on VMS).
- **Phase 15**: fixtures on the guest, the AST fixtures repeated, and the
  Phase 14 suite still clean.
- **Phase 16**: the direct-object bootstrap fixed point on the guest, with
  no `MACRO` in the build, and every earlier VAX fixture identical whether
  built through `.mar` or directly.
