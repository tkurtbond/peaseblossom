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
    Err.Mod                  -- Out on standard error, not Oakwood (Phase 11 A26)
    FormattedOutput.Mod      -- the formatting Out and Err share, by descriptor (Phase 11 A26)
    FileDescriptorOutput.Mod -- write(2)/isatty under them, apart so voc compiles the rest (Phase 11 D11)
  voc/
    FileDescriptorOutput.Mod -- the same over voc's Platform, for Stage 0's Err (Phase 11 D11)
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
| 12 | Library/module support beyond Phase 10 | voc-option triage, static/dynamic library building, voc module inventory, voc's runtime modules and finalization | LLVM | poc (self-hosted) |
| 13 | MACRO-32 | `VaxTypes`, `VaxCodeGenerator`, `VaxToolchainDriver` (stub) | VAX (scoped, unverified) | poc (self-hosted) |
| 14 | Running on VAX/VMS | `VaxToolchainDriver` (real), `rtl/vax` (minimal), VAX backend widened to what poc's own source needs | VAX (assembled, linked, run) | poc on VAX/VMS compiles itself |
| 15 | Library/module support on VAX/VMS | VMS libraries (object, shareable), ported Oberon modules, native VMS libraries, AST support | VAX | poc on VAX/VMS |
| 16 | Direct VAX/VMS object files | `VaxInstruction`/encoder, `VaxObjectWriter` (`.OBJ`), debug/traceback records | VAX (no assembler in the loop) | poc on VAX/VMS |
| 17 | Further extensions to Oberon-2 | record and array literals, and whichever other extensions it adopts | both | poc (self-hosted) |
| 18 | voc's library modules | the chosen modules of voc's `src/library` | LLVM | poc (self-hosted) |

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

**Done** (closed 2026-09-26; `doc/phase-11-inventory.md` lists every item
and its verdict). The full account - design, every step, what was found and
decided along the way, testing - is in `doc/phases/phase-11.md`, under the
same step numbers:

- **1.** Inventory and reconciliation.
- **2.** Known defects and unfinished corners.
- **3.** Run-time semantics.
- **4.** Can the collector do better than scanning the stack conservatively?
- **5.** Debugging support for `gdb` and `lldb`.
- **6.** Language-extension decisions.
- **7.** An `Err` module.
- **8.** Nested procedures.
- **9.** Close-out.

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
   **Done (2026-09-27, decided with the user): `doc/voc-options.md`** has the
   table, every option probed against voc. Adopted: `-r` as `-range-checks`
   (`SHORT` of an integer and `CHR` that do not fit trap, status 14, off by
   default), `-M` as `-static`, `-V` as `-verbose` (the clang command), and
   voc's `LDFLAGS`/`LDLIBS` as a repeatable `-link <arg>`. No switch turns a
   check off (`-a`, `-t`, `-x`, `-p`: A14 and D16 stand). `-S`/`-m` are
   `-emit-llvm-ir`/`-build`; `-c` goes to step 2; `-e`/`-s`/`-F`, `-f`,
   `-OV` and `-A..` do not apply. The triage found two checks the report
   requires that voc makes and poc did not, now always on: a function that
   reaches its `END` (status 12) and a record assigned to a `VAR` parameter
   or `p^` whose dynamic type extends its static type (status 13); and, on the
   way, a bare `RETURN` in a function (now a compile-time error), a record
   assignment to a `WITH`-narrowed `VAR` parameter that copied only the base
   record's fields (fixed), and flags with no command after them, which
   exited 0 having done nothing (now the usage text, status 1). Fixtures
   `llvm-range-checks`, `llvm-return-trap`, `llvm-record-assign-trap`,
   `semantic-reject-bare-return`, `poc-link-flags`, `poc-usage`.

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

   **Design (decided with the user 2026-09-27).** Four decisions, then
   what follows from them.

   - *Every module is compiled on its own* (as voc does), library or not:
     one `.ll` and one object per module, which declares what it uses of
     its imports. `-build` compiles each module of the program found as
     source and links the objects; cross-module inlining is given up.
   - *Initialization is voc's*: each module's `_init` has a flag of its
     own, returns at once when it is set, and otherwise sets it, calls the
     `_init` of each of its imports in declaration order, and runs the
     module's body. `main` sets the stack base and calls the main module's
     `_init` only, so a program needs no list of the modules a library
     keeps to itself, and the order does not depend on the link.
   - *A library is a named set of modules, and rtl/llvm is one*:
     `poc -library <name> [-output-dir <dir>] <file>...` compiles the files
     named (and nothing else: every import must be one of them or come from
     a library already on the library path) and writes, into
     `<dir>/<triple>/<O2|OC>/` (a library is specific to its target and size
     model, and so are its `.sym` files, which carry folded constants: B1),
     `lib<name>.a`, `lib<name>.so`, each module's `.sym` and a manifest,
     `<name>.library` (its modules with their keys and imports, the
     libraries it needs, the triple and size model). A module belongs to
     exactly one library: poc refuses to build a module into a library when
     one on the library path has it already, and to link two libraries that
     both have it, so a process never holds two collectors. rtl/llvm is the
     library `poc-rtl`, built by `make` for the host, both size models. A
     program links its libraries statically; `-shared-libraries` links them
     dynamically, with a run-time search path (`-rpath`) naming each one's
     directory.
   - *Module keys, checked twice*: each module's object defines the symbol
     `<Module>.-key.<hash>`, the hash that of its `.sym` text, and every
     importer's object references it, so a link against a module whose
     interface changed after the importer was compiled fails in the linker
     whoever runs it. poc also compares, before it links, the keys each
     library's manifest records for its own imports with the keys of the
     libraries it will link, and names the stale library in a message of
     its own.

   Following from those (poc's own choices, open to change):

   - The library path is `-library-path <dir>` (repeatable, like
     `-import-path`), seeded from `POC_LIBRARY_PATH` and, last, the `lib/poc`
     directory beside the directory poc's executable is in. A module an
     import names is taken from a library when a manifest on the path has
     it, otherwise from source on the import path. When no `poc-rtl` exists
     for the target and size model (a cross build, a fixture that sets no
     library path), rtl/llvm is found as source like any module and
     compiled into the program, as today.
   - `-emit-llvm-ir <file>` writes the `.ll` of every module of the program
     compiled from source (the one named has `main`), where `-build` would;
     `-build` writes each module's `.ll` and object there too, so a build's
     output directory fills with them as it fills with `.sym` files today.
   - Objects for a library are position-independent, and the same objects
     go into both the archive and the shared library. Symbols keep their
     default visibility: an extension's method table can name an imported
     record's hidden type-bound procedure, so nothing a module defines can
     be assumed private to it. What a module makes for itself alone - an
     anonymous record's type descriptor and initialization procedure,
     strings, trap messages - is `internal`/`private`, so two objects never
     both define it.
   - voc's `-c` (compile, do not link) gets no flag of its own for now:
     `-library` already compiles without linking a program, and
     `-emit-llvm-ir` writes every module's `.ll`.

   **Sub-steps**, each its own commit, each passing `make check`:
   **2a** per-module code generation and voc's initialization (no libraries
   yet: `-build` compiles the program's modules one by one and links them);
   *done 2026-09-27*: `LLVMCodeGenerator.GenerateModule` writes one module's
   IR, declaring everything each module of its import closure defines (and
   the runtime modules' the generated code calls without an IMPORT; an
   unused declaration costs nothing), and a guarded `_init` that calls its
   imports' in IMPORT-list order (voc's is alphabetical, from its sorted
   scope). `main` also calls `ModuleTable_init` and
   `GarbageCollectedHeap_init` before the main module's, since no IMPORT
   names them. Not yet `internal`: an anonymous record's descriptor and
   initialization procedure keep their module-prefixed global names, since
   in one run another module may still name another's (2c changes that);
   fixture `llvm-module-init-order`;
   **2b** module keys; *done 2026-09-27*: `ModuleInterface.KeyOf` gives
   the 64-bit FNV-1a hash of a module's `.sym` bytes (computed a byte at a
   time, so poc needs no 64-bit integer for it), recorded whenever a run
   writes or reads a `.sym`; whole-program commands now write the main
   module's `.sym` too, so every module has one. Each module's `.ll`
   defines `@<M>.-key.<hash>` and lists its imports' keys in
   `@<M>.-imports`, kept by `@llvm.used`; fixture `llvm-module-keys`
   (a new body relinks, a new interface fails in the linker naming the
   key); **2c** `-library`, the manifest, the library path,
   static and dynamic linking, and the refusal of a second copy of a module;
   *done 2026-09-27*: `src/driver/Libraries.Mod` (the library path, manifests,
   `<Module>.owner` files naming a module's library - no directory listing
   needed -, link order, and the refusals: a module two linked libraries
   both have, a library compiled against a key another library no longer
   has, a needed library missing); `poc -library`, `-library-path`,
   `-clear-library-path` (which also leaves out `POC_LIBRARY_PATH` and
   poc's own `../lib/poc`, found through the shell's `command -v`),
   `-print-library-path`, `-shared-libraries`. A module a library has
   enters the program from its `.sym` (`ModuleList.inLibrary`, declared
   and not generated; `ModuleInterface.libraryLookup` makes the checker
   read the library's `.sym`). Libraries' objects are `-fPIC`; the shared
   library is `lib<name>.so` (`.so.0.0` on OpenBSD) and is linked against
   the libraries it needs; `-shared-libraries` gives the program an
   absolute run-time search path. The descriptor and initialization
   procedure of a record with no name are now `internal`. Fixture
   `llvm-libraries`;
   **2d** `poc-rtl`, built by `make`, used by default when present;
   *done 2026-09-27*: `make` builds `rtl/llvm` as the library `poc-rtl`
   into `build/lib/poc/<host triple>/{O2,OC}` (and Stage 1's into
   `build/stage1/lib/poc`, `check-opt2`'s into `build/opt2/lib/poc`), where
   each poc's default library path finds it, so a program links
   `libpoc-rtl.a` instead of compiling the runtime again. A library
   module's `.sym` cannot say whether its bodies call `NEW`, so a program
   with a module from a library gets the collector whenever a library on
   the path has `GarbageCollectedHeap`. The bootstrap stages build with
   `-clear-library-path` (poc from source, independent of any library;
   the fixed point compares every module), and so do the fixtures that
   show or relink the objects compiled from source (`llvm-module-keys`,
   `poc-link-flags`); **2e** using modules and libraries (added with the
   user 2026-09-27, after trying four ways a program gets its modules with
   the 2d poc): (1) the program's own modules and poc's runtime, which
   works with no flags, the runtime linked from `poc-rtl`; (2) modules
   someone else shared, which work as source through `-import-path`
   (compiled with the program, their `.sym`/`.ll`/`.o` written beside it)
   but not as `.sym` and `.o` files alone ("cannot find source"); (3) the
   user's own library, which works (`-library`, then `-library-path`,
   statically or with `-shared-libraries`); (4) several libraries from
   others, which works too: a library's needs are linked after it, and a
   library compiled against another's old key is refused with a message
   that names both. What falls short, and this sub-step does:
   - Diagnostics. A module found nowhere gives only "unknown imported
     module", in the program or, for a library's missing need, in the
     library's `.sym` (`Loud.sym:2:10`). The message is to say what was
     searched - the import path and the library path, and the triple and
     size model the library was looked for under, so a library built for
     `-O2` only is recognized as such under `-OC` - and, for a library
     whose needed library is not on the path, name both libraries.
   - Shadowing. A library module is taken in preference to source of the
     same name, and the first library on the path that has a module
     shadows the others (a module in two libraries is refused only when
     both are linked). Both are to be warned about, naming what was
     passed over; the rules themselves stay.
   - Compiled modules outside a library: decided, not supported. A library
     is the only compiled form poc takes (one module is a library too), so
     the key checks stay in one place; the "cannot find source" message is
     to say so and point at `-library`.
   - Installation: `poc -install-library` copies a library's files for one
     triple and size model into `<prefix>/lib/poc/<triple>/<O2|OC>/`, by
     default the `../lib/poc` an installed poc already searches, so every
     build finds it with no flag; and a program linked with
     `-shared-libraries` finds its shared libraries through a run-time
     search path that survives moving the program and its libraries
     together (`$ORIGIN`-relative, to be checked on each of the four
     systems), not only the absolute directory it was built against.
   - Deferred, not in this sub-step: incremental builds (skipping a
     module whose source and imports' keys are unchanged; every `-build`
     now compiles every module that is not in a library).
   Fixtures: each of the four ways, with the messages and warnings above
   as golden output. *Done 2026-09-27*: an import found nowhere is followed
   by notes (`Diagnostics.Note`, through the hook
   `ModuleInterface.explainMissingModule`): the files looked for and
   where, the library path for the triple and size model, a library that
   has the module for the other size model, a library's need that is
   missing; its uses are not each reported again. A `.sym` without source
   names the file and points at `-library`. A manifest records each
   module's source hash (`source <Module> <key>`), so source beside the
   program is warned about only when it differs from the library's; a
   library whose module an earlier one on the path has is warned about
   (`Libraries.WarnHidden`). `poc -install-library <name>` (to
   `-output-dir`, else poc's `../lib/poc`: `Libraries.PocLibraryDir`)
   copies the manifest, archive, shared library, `.sym` and `.owner` files,
   replacing an earlier copy and refusing a module another library there
   has. The run-time search path is each library's directory relative to
   the executable's or shared library's (`$ORIGIN/...`, when they share a
   directory other than the root), then the absolute one; a shared library
   also has `$ORIGIN`, and both are linked with `-z origin`, without which
   OpenBSD's `ld.so` does not expand `$ORIGIN`. `check-opt2` gives each of
   its two suites' poc `poc-rtl` in its own `../lib/poc`, as `make` does
   (the Stage 0 poc copied to `build/opt2/stage0/bin`); 2d's optimized
   Stage 1 had found none, and compiled the runtime from source. Fixture
   `llvm-using-modules`;
   **2f** compiled modules without source (decided with the user
   2026-09-27, reversing 2e's "a library is the only compiled form": some
   people do not want to share source). Both `-build` and `-library` take
   a module given as its `.sym` and `.o`, found together on the import
   path, when there is no source for it (source still wins, so a stale
   `.sym` never outranks it). The object describes itself, read with `nm`
   (on Linux and all three BSDs): its key symbol names the size model too,
   `<Module>.-key.<O2|OC>.<hash>`, so an importer linked with an object of
   the other model fails in the linker as a stale interface does, whoever
   links it; a marker symbol, `<Module>.-target.<triple>`, defined and
   never referred to, names the triple, which poc checks (the linker does
   not tell x86_64 Linux from x86_64 FreeBSD); its undefined `-key.`
   symbols are its imports and the keys it was compiled against; an
   undefined `GarbageCollectedHeap` symbol says it uses the collector. poc
   checks the pair: the `.o` must define the key of the `.sym`'s hash, for
   this triple and model, and each import must be source, a pair or in a
   library, with the key the `.o` names. A pair's `.o` goes on the link
   line; `-library` takes pairs as members, the manifest's keys from the
   `.sym` and `nm`, and no `source` line. Objects are compiled
   position-independent (`-fPIC`) always, not only for a library, so a
   `-build` object can go into a shared library. `poc -compile` makes a
   module's `.sym` and `.o` without a program. Fixtures: a program and a
   library built from pairs; the refusals (a `.o` that does not match its
   `.sym`, another triple, another size model, an import with another
   key). *Done 2026-09-27*: `LLVMCodeGenerator.KeySymbol` names the model,
   `EmitModuleKeys` defines the target marker; `Libraries.ReadObject` runs
   `nm -P`; `Poc.DiscoverCompiledModule` checks a pair and enters it as
   `ModuleList.compiled`, declared and not generated, its `objectPath`
   linked (and the collector added when its object calls it). The pass
   that regenerates `.sym` files from source now also follows a `.sym`'s
   imports, so an import of a pair still gets its `.sym` from its source.
   `poc -compile <file>...` (voc's `-c`, added to 2f with the user the
   same day) compiles the modules named to `.sym`, `.ll` and `.o`, with no
   `main` and nothing linked (`Poc.CompileOnly`, `LLVMToolchainDriver.
   Compile`); their imports are checked, not compiled, and a module named
   is compiled even when a library on the path has it (poc -library's
   files and -compile's are both `members`; only -library requires every
   import to be one or in a library, `membersOnly`). Fixture
   `llvm-using-modules` (sections 2 and 5);
   **2g** whole-program optimization, `poc -lto` (decided with the user
   2026-09-27). Opt-in, the default link unchanged: LTO links are slower,
   and IR and bitcode are tied to the LLVM version that reads them, where
   an object is not. With `-lto`, `-build` compiles each module's `.ll` to
   LLVM bitcode (`clang -flto -c`) and links with `-flto`, so LLVM
   optimizes the modules as one program: inlining across modules, removing
   procedures nothing calls, folding across module boundaries. What takes
   part: the program's own modules; a module given as its `.sym` and `.ll`,
   a third kind of pair beside 2f's `.sym` and `.o`, its key, target and
   imports read from the `.ll` text instead of with `nm` (and refused with
   a clear message when this clang cannot read it); and libraries built
   with `-lto` (`poc-rtl` too, when `make` is asked for it), whose archive
   holds bitcode. A `.sym`/`.o` pair and a library of ordinary objects
   still link, without optimization across their boundary. `-compile
   -lto` writes a module's bitcode `.o`. Toolchain, probed 2026-09-27 with
   a two-file `.ll` LTO build: the default linker works on atla (GNU ld
   2.46 with LLVM's plugin; no `ld.lld`), cymoril (lld 19) and alerik (lld
   19); on artos GNU ld 2.42 fails and pkgsrc's `ld.lld` works, so on
   NetBSD poc passes `-fuse-ld=lld`; rackhir not yet probed. Little to gain
   on 32-bit x86, whose default is `-O0` (x87 reals). The key and target
   symbols are constants kept alive, so the checks of 2b and 2f still hold
   under LTO. A `.ll` is readable IR, much easier to reverse than an
   object: `.sym`/`.ll` is for optimization, not for sharing a module
   without its source. Fixtures: a program built with `-lto` from source,
   from a `.sym`/`.ll` pair and with an LTO `poc-rtl`, with the same output
   as without; a cross-module call inlined (the optimized IR or the
   executable's symbols); a `.ll` for another target or size model
   refused. *Done 2026-09-27*: `LLVMToolchainDriver.lto` adds `-flto` to
   each `clang -c` and to the link (and `-fuse-ld=lld` on NetBSD,
   `AppendLTOOptions`); `ltoLink` does the same for a link with an LTO
   library's archive in it, since a link without `-flto` fails on bitcode
   with GNU ld (atla, artos), so a library built with `-lto` (manifest line
   `lto`, `Library.lto`) can be linked by a program built without it; its
   shared library is ordinary code. What is beside a `.sym` with no source
   (`Poc.CompiledFiles`): the `.ll` when there is one and `-lto`, no `.o`,
   or a `.o` that is bitcode; else the `.o`. A bitcode `.o` alone is
   refused (nm cannot read bitcode on OpenBSD or NetBSD): give its `.ll`.
   `Libraries.ReadIR` reads the key, target and imports from the `.ll`
   text; the module enters the program with `ModuleList.irPath` and is
   compiled to `<Module>.ir.o` in the output directory, so that a `.o`
   beside the pair is never overwritten; `-library` given a `.sym`, `.o` or
   `.ll` takes the same one, copying the `.ll` into the library to compile
   to `<Module>.o` there. A `.ll` clang cannot compile gets a note that it
   may be from another LLVM version. For 32-bit x86 NetBSD `-lto` is
   dropped with a warning: GNU ld cannot link bitcode, and lld's i386
   executables fail to run there even for plain C (probed on artos, NetBSD
   11 amd64). `make check-lto` (not part of `check`)
   runs the suite with a wrapper that adds `-lto`, against a `poc-rtl`
   built with it, as `check-opt2` does. Fixture `llvm-lto`;
   **2h** the fixtures this step's testing paragraph asks for, on Linux and
   the BSD hosts, at both word sizes, and the rackhir run of step 2's
   commits. *Done 2026-09-27*: fixture `llvm-libraries-i686` builds
   `llvm-libraries`' two dependent modules into a library for 32-bit x86
   (`i686_triple`: i686 Linux on atla, `-m32` on the BSDs, the host's own
   on cymoril), on a `poc-rtl` built for it, under `-O2` and `-OC`, and
   links and runs a program with it statically and dynamically (the
   shared one only where a 32-bit program can use a shared library,
   `i686_can_run_shared`: NetBSD amd64's 32-bit compatibility has static C
   libraries only, so there it fails with "Exec format error" even for
   plain C); the
   64-bit side is `llvm-libraries`, `llvm-using-modules` and `llvm-lto`.
   Its failures are messages: a library whose needed `poc-rtl` is not on
   the path (the notes say so), and a `.sym` that does not match its
   library's manifest. `llvm-lto` had no comparison with its golden
   (`testresult.sh` missing), now fixed. rackhir (FreeBSD arm64) ran
   `gmake check` on `6285c40`, which has every step 2 commit through 2g:
   295/295 under Stage 0 and Stage 1, Stage 1 and Stage 2 identical.

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
   (not yet looked at at all) filled in like the rest. *Done
   2026-09-27*: `doc/voc-module-inventory.md`, all 161 files, with for
   each what voc builds (its `-OC` library is the runtime only), what
   poc's front end makes of it today (`poc -emit-interface` in import
   order against poc-rtl's interfaces: 23 accepted, 34 after the
   language fixes below), and the findings
   step 4 and Phase 18 start from. Most of the library stops on what poc's
   `Platform`, `Files` and `Modules` lack; ten modules hold voc's inline
   C; s3's zlib is Oberon, not C; and six language points came up, among
   them a conformance bug (a one-character string constant compared
   with a `CHAR`, and a character constant used as a string, `Oberon2.pdf`
   §3). A trap in the checker on a record whose base came from a module
   that could not be imported was fixed on the way
   (`semantic-reject-unresolved-record-base`). The user's decisions on
   the language points (2026-09-27): the §3 rule fixed both ways; text
   after `END M.` ignored; a 16-digit hexadecimal constant above
   `MAX(HUGEINT)` taken as a 64-bit pattern, as voc does, unless
   `-strict`; `LONG` of a `CHAR` stays an error; `POINTER [1] TO` is not
   adopted (a port uses `SYSTEM.ADDRESS`); a function with an empty body
   stays an error (a port removes `ulmSYSTEM`'s two). `tools/voc-inventory/
   inventory` regenerates the tables (to rerun when poc's runtime or
   front end changes what they say).

4. **Deciding what poc supports.** *Decided with the user 2026-09-27*:
   for now poc offers modules compatible with voc's **runtime** modules
   (`src/runtime`), and everything under `src/library` (`v4`, `ooc`,
   `ooc2`, `oocX11`, `s3`, `ulm`, `misc`, `pow`) moves to Phase 18, to be
   considered after all the other phases, with step 3's inventory as its
   starting point. Of the runtime:
   - **`Heap` is not provided.** Nothing under `library/` imports it; only
     voc's own `Files` and `Modules` do. Most of it is voc's code
     generator's interface to its runtime (`REGMOD`, `REGTYP`, `REGCMD`,
     `INCREF`, `NEWREC`, `NEWBLK`, `InitHeap`), which poc's code
     generator has its own form of; `Lock`/`Unlock` serve voc's
     signal-driven interrupts, `FileCount` is a counter nothing reads,
     `FreeModule` unloads nothing, `TAS` is Ulm's non-atomic
     test-and-set. Its collection and statistics are in
     `GarbageCollectedHeap` already (`Collect`, `LiveBytes`,
     `HeapBytes`, `SetChunkSize`); no thin `Heap` over them (user's
     decision).
   - **Finalization is taken from it**: poc's collector gets `Heap`'s
     `RegisterFinalizer(obj, finalize)`, and poc's `Files` uses it as
     voc's does, so a `File` dropped without `Close` is still closed
     and its buffer written when it is collected.
   - **Everything else in the runtime is made interface-compatible**
     with voc's: `Files`, `In`, `Modules`, `Platform` (the Unix
     variant), `Oberon`, `Reals`, `Texts` and `VT100`; `Out`, `Strings`,
     `Math` and `MathL` already are. `Console` (voc's `library/v4`) and
     `Err` stay as they are.

5. **Implementing the runtime modules.** Each is ordinary Oberon-2 in
   `rtl/llvm`, built into `poc-rtl`, with `["C"]` external procedures
   where voc's has inline C, and written for all four Unix-likes (the
   standing rule for `rtl/llvm`). What each lacks is measured from the
   modules' exports (2026-09-27; a name counts once, whatever its kind).
   Where poc cannot or will not match voc (a Linux-only call, a detail of
   voc's own layout), the difference is decided with the user and
   written down. **Testing**: per substep, compile+link+run+diff fixtures
   compared with the same program under voc, as Phase 9's were. The
   substeps follow the modules' imports (voc's `Texts` imports `Files`,
   `Modules` and `Reals`; `Oberon` imports `Texts` and `Modules`; `Reals`
   needs `Platform.LittleEndian`), each its own commit:

   - **5a. `Platform`** (5 of 46 procedures; the base the rest need):
     files by handle (`OldRO`, `OldRW`, `New`, `Close`, `Read`,
     `ReadBuf`, `Write`, `Seek`, `Size`, `Truncate`, `Sync`, `Rename`,
     `Identify`, `IdentifyByName`, `SameFile`, `SameFileTime`,
     `SetMTime`, `SetFileMTime`, `MTimeAsClock`, the error tests
     `Absent`, `Inaccessible`, `TooManyFiles`, `NoSuchDirectory`,
     `DifferentFilesystems`, `Interrupted`, `TimedOut`,
     `ConnectionFailed`, `Error`), time (`Time`, `GetClock`,
     `GetTimeOfDay`, `Delay`), memory (`OSAllocate`, `OSFree`), the
     signal handlers (`SetInterruptHandler`, `SetQuitHandler`,
     `SetBadInstructionHandler`), `getEnv`, `IsConsole`,
     `MaxNameLength`, `MaxPathLength`; and the types and constants
     `FileHandle`, `FileIdentity`, `LittleEndian`, `NL`,
     `SeekSet`/`SeekCur`/`SeekEnd`, `StdIn`/`StdOut`/`StdErr`.
     **Done (2026-10-02).** Decided with the user: what differs between
     the four systems (open's flags, errno and its values, `struct stat`,
     the clock, signals, NetBSD's renamed functions) is in
     `rtl/llvm/Platform.c`, and poc compiles a module's sibling `.c` with
     it wherever it compiles the module (`doc/llvm-toolchain.md`, "A
     module's part in C"; fixture `llvm-c-part`). An error code is now
     errno's value, as voc's (it was -1; `Files.Delete`/`Rename` too).
     Differences kept: `Write` writes everything and `Delay` sleeps the
     whole time (voc's make one call each); `StdIn`/`StdOut`/`StdErr` are
     exported with `*` where voc's have `-`: voc accepts the read-only mark
     on any declaration but gives it a meaning only on variables and record
     fields (`OPP.CheckMark`), so on a constant it is a plain export, and
     poc keeps rejecting it there (decided with the user 2026-10-02). Fixture
     `llvm-platform-files` (44 checks, against voc, both size models).
   - **5b. `In.Name` and `VT100`** (new: terminal control sequences);
     small, needing nothing else.
   - **5c. Finalization** in `GarbageCollectedHeap`, from voc's `Heap`
     (`RegisterFinalizer(obj, finalize)`): registered objects are weak
     references, not roots; one unreachable after marking is kept for its
     finalizer, which runs after the collection. Decided here: whether
     finalizers also run when the program ends (voc runs them only from
     `Modules.Halt` and `AssertFail`) and when it traps. A collector
     change, so rackhir runs after it.
   - **5d. `Files`** (15 of 37): the typed riders (`Read`/`Write` of
     `Bool`, `Byte`, `Bytes`, `Int`, `LInt`, `Real`, `LReal`, `Set`,
     `Num`), `GetDate`, `GetName`, `Purge`, `ChangeDirectory`,
     `SetSearchPath`, `MaxNameLength`, `MaxPathLength`; and 5c's
     finalization of a `File` dropped without `Close`, as voc's does.
   - **5e. `Modules`** (4 of 9): `Halt`, `AssertFail`, `Free`,
     `res`/`resMsg`, `imported`/`importing`, `BinaryDir`, and `ThisMod`/
     `ThisCommand` in full, as voc (user, 2026-09-27): each module's
     `_init` registers its name and its commands - exported procedures
     with no parameters and no result, as voc's `OPC.RegCmds` picks them -
     so a program finds a module of its own by name and calls a command
     of it by name (`Texts.Load` recreates a text's elements this way;
     a command dispatcher is the other use). poc's `Modules` declares its
     own `Module`, `ModuleName`, `Cmd` and `Command` (voc's are `Heap`'s);
     the registration extends the per-module table `ModuleTable` already
     keeps for the collector. As in voc, a module is found only once its
     `_init` has started, only modules linked into the program exist, and
     `Free` unloads nothing. The cost, to note in the documentation: a
     command is referenced from its module's table, so neither the
     linker nor `-lto` drops an unused one. Code generator work, so
     rackhir runs after it; split in two if the registration grows large.
   - **5f. `Reals`** (new; 10 procedures, the conversions `Texts` uses).
   - **5g. `Texts`** (new; voc's file-based texts, readers, scanners and
     writers, no display: 38 procedures).
   - **5h. `Oberon`** (new; the stub system module: `Log`, `Par`,
     `Time`, `GetClock`).

6. **Exit gate.** Every runtime module of step 5 builds into `poc-rtl`,
   static and shared, and passes its fixtures at both word sizes on
   Linux and the three BSDs, with `make check` clean on each - the same
   bar as Phase 9 step 9 - and on rackhir (arm64) at the close-out.

**Testing summary**: steps 1, 3 and 4 are decisions with written
artifacts (tables and a design), verified against the primary sources
they cite; steps 2 and 5 are compile+link+run+diff fixtures; step 6 is
the whole-matrix gate.

**Deferred here from Phase 11 (2026-09-26): the lowest 32-bit x86 CPU.**
poc passes clang no `-march`, so each OS's default CPU applies: pentium4
for i686 Linux (which may use SSE2), i486 for NetBSD, i586 for OpenBSD,
i686 for FreeBSD. poc must run on a Pentium II (i686, no SSE), so the
question is whether to fix `-march=i686` for every 32-bit x86 triple:
the same code on all four OSes and no SSE2 on Linux, at the cost of 486
and Pentium machines. x87 reals stay either way. It needs 32-bit x86 test
hosts first: a 32-bit NetBSD at least, and a 32-bit FreeBSD if FreeBSD
still ships an i386 build (today only OpenBSD, cymoril, is 32-bit x86).

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
   modules track the kit they came from. STARLET's definitions are written
   in SDL, which renders them for each language (the macros in
   `STARLET.MLB`, VAX C's `ssdef.h` and the rest); the user maintains an
   UNSDL utility on a VAX that extracts much of that information, a
   likely starting point for the generator. The modules keep the system's
   names, `_` and `$` included (Phase 11 A25); SDL's unions and bit fields,
   which an Oberon record cannot express, need a convention of their own. Implement it, and write the
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

### Phase 17 — Further extensions to Oberon-2

**Goal**: settle the language extensions that are larger than Phase 11's -
each a design of its own, through the front end, the `.sym` format and both
backends - and implement the ones adopted. As in Phase 11, each starts with
a survey of what other Oberons do (and Modula-2/-3 where they are the only
precedent) and ends with the user's decision; "not adopted" is a legitimate
result, recorded in `doc/language-extensions.md` like the others.

**Candidates** (from `000-todo.org`'s Extensions list and Phase 11's
inventory):

1. **Record and array literals** (Phase 11 A24, moved here 2026-09-26).
   `doc/initializers-and-literals-survey.md` has the survey: no Oberon has
   record literals; A2's `[1, 2, 3]` builds its mathematical arrays only;
   Oberon+ lists both as TODO; ISO Modula-2 and Modula-3 have typed value
   constructors, `T{...}`. A typed form is the likely starting point. Open:
   `CONST` declarations of structured type (and so structured constants in
   `.sym` files), open arrays and pointers inside a literal, positional or
   named fields, and what a record extension's literal holds.
2. **Slices of one-dimensional arrays** (`000-todo.org`).
3. **voc's read-only parameters, `x-`** (`000-todo.org`; considered and not
   adopted in Phase 11, `doc/language-extensions.md`).
4. **The terminator-based `ARRAY OF CHAR` assignment rule** (`000-todo.org`;
   decided against in Phase 11 A21, to reconsider).

**Exit gate**: every candidate has a recorded decision; each adopted one has
fixtures, is rejected by `-strict`, and passes `make check` on Linux and the
three BSDs (and, once Phase 14 exists, on VAX/VMS).

### Phase 18 — voc's library modules

**Goal**: decide which of the modules under voc's `src/library` poc
offers, and build those. Moved here from Phase 12 step 4 (user,
2026-09-27): Phase 12 makes poc compatible with voc's runtime modules
only, and the libraries wait until everything else is done.

**Starting point**: Phase 12 step 3's inventory,
`doc/voc-module-inventory.md` (regenerated by `tools/voc-inventory/
inventory`, since Phase 12's runtime work changes what poc accepts),
with its findings: most of the library reaches voc's `Platform`; ten
modules hold voc's inline C; s3's zlib is Oberon, not C; only `oocX11`
needs an outside C library (Xlib); the families overlap heavily
(strings, random numbers, real conversion, sets); several modules are
written for one machine (`ulmMC68881`, `ulmSys`); the licences differ
(LGPL for OOC and Ulm, the ETH Oberon licence for s3, whose text is
still to be fetched, none for `powStrings` and `Listen`).

**Steps**: sort every module into wanted (with a priority), deferred or
not wanted, with the reason. Criteria: how useful it is to a program
written against voc; whether it can be written for all four Unix-likes;
whether it needs an outside C library; how much of it is the host
Oberon *system*; its licence; and the cost. Then implement the wanted
ones into a library of their own, with fixtures compared with voc, and
the same exit gate as Phase 12 step 6.

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
