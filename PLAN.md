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
| VAX/VMS backend | Phase 15 emits MACRO-32 assembly text only (hand-reviewed, non-executable); assembling/linking/running under VMS 5.5-2 (SIMH or real hardware) was deferred at first and is now Phase 16, ending with poc bootstrapping itself on VAX/VMS; Phase 17 adds VMS library/module support, and Phase 18 has poc write `.OBJ` files itself instead of MACRO-32 text |
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
      VaxToolchainDriver.Mod -- stub only; no assemble/link/run (Phase 15)
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
    FormattedText.Mod        -- the text of Out's numbers, shared with OutStr ("Ongoing library enhancements")
    OutStr.Mod, InStr.Mod    -- Out's output into a string, In's input from one ("Ongoing library enhancements")
    FormattedInput.Mod       -- the tokens In and InStr read, over a Source ("Ongoing library enhancements")
    FileDescriptorOutput.Mod -- write(2)/isatty under them, apart so voc compiles the rest (Phase 11 D11)
  voc/
    FileDescriptorOutput.Mod -- the same over voc's Platform, for Stage 0's Err (Phase 11 D11)
  vax/                        -- deferred stubs only until Phase 16 (minimal runtime), Phase 17 (libraries)
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
| 13 | Packaging and documentation | `make install`, the bootstrap seed, `make dist`, OS packages, the User's and Reference Guides, `poc(1)` | LLVM | poc, or the seed with clang alone |
| 14 | Record and array literals, structured constants | `T{...}` through `SyntaxTree`, `Parser`, `SemanticActions`, `ConstantEvaluator`, `ModuleInterface` and `LLVMCodeGenerator` | LLVM | poc (self-hosted) |
| 15 | MACRO-32 | `VaxTypes`, `VaxCodeGenerator`, `VaxToolchainDriver` (stub) | VAX (scoped, unverified) | poc (self-hosted) |
| 16 | Running on VAX/VMS | `VaxToolchainDriver` (real), `rtl/vax` (minimal), VAX backend widened to what poc's own source needs | VAX (assembled, linked, run) | poc on VAX/VMS compiles itself |
| 17 | Library/module support on VAX/VMS | VMS libraries (object, shareable), ported Oberon modules, native VMS libraries, AST support | VAX | poc on VAX/VMS |
| 18 | Direct VAX/VMS object files | `VaxInstruction`/encoder, `VaxObjectWriter` (`.OBJ`), debug/traceback records | VAX (no assembler in the loop) | poc on VAX/VMS |
| 19 | Further extensions to Oberon-2 | whichever other extensions it adopts | both | poc (self-hosted) |
| 20 | voc's library modules | the chosen modules of voc's `src/library` | LLVM | poc (self-hosted) |

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
decided along the way, testing - is in `doc/history/phases/phase-08.md`, under
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
decided along the way, testing - is in `doc/history/phases/phase-09.md`, under
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
decided along the way, testing - is in `doc/history/phases/phase-10.md`, under
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

**Done** (closed 2026-09-26; `doc/history/phase-11-inventory.md` lists every item
and its verdict). The full account - design, every step, what was found and
decided along the way, testing - is in `doc/history/phases/phase-11.md`, under the
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
backend (Phase 15) because the library question is an LLVM/Unix one and
nothing in the VAX work depends on it.

**Done** (closed 2026-10-02). The full account - design, every step, what
was found and decided along the way, testing - is in `doc/history/phases/phase-12.md`,
under the same step numbers:

- **1.** Which of voc's command-line options poc needs (`doc/developer/voc-options.md`).
- **2.** Building static and dynamic libraries with poc: 2a per-module code
  generation, 2b module keys, 2c `-library`, 2d `poc-rtl` built by `make`,
  2e using modules and libraries, 2f compiled modules without source
  (`-compile`), 2g `-lto`, 2h the fixtures.
- **3.** A complete inventory of the libraries and modules voc supplies
  (`doc/research/voc-module-inventory.md`).
- **4.** Deciding what poc supports: voc's runtime modules; its `src/library`
  waits for Phase 20.
- **5.** Implementing the runtime modules: 5a `Platform`, 5b `In.Name` and
  `VT100`, 5c finalization, 5d `Files`, 5e `Modules`, 5f `Reals`, 5g
  `Texts`, 5h `Oberon`.
- **6.** Exit gate.

### Phase 13 — Packaging, installation, and the User's and Reference Guides

**Inserted 2026-10-02 (user)**, before the VAX/VMS work: the phases after it
were renumbered, so the old Phases 13-18 are now 14-19. Records of closed
phases (`doc/history/phases/`, `doc/history/phase-11-inventory.md`, `doc/history/project-history.md`,
`doc/research/initializers-and-literals-survey.md`) keep the numbers they were
written with: there, "Phase 13" is today's Phase 14, and so on up to "Phase
18", today's 19. A second renumbering followed the same day, when record
and array literals became Phase 14 (user, 2026-10-02): the Phases 14-19
of that first renumbering are now 15-20, so a record written between the
two (`doc/history/phases/phase-12.md`) means today's 15-20 by its 14-19.

**Goal**: make poc something a person who did not build it can install
and use, on Linux and the three BSDs. That means an installed poc that
needs only clang and the C library (not voc, not the source tree), a way
to build it from source without voc, a release that can be downloaded, OS
packages, and the documentation to go with them: a User's Guide (how to
use poc), a Reference Guide (what exactly poc accepts and does), and a
`poc(1)` manual page. Placed before the VAX/VMS backend because it is
about the LLVM backend people can run today, and because writing the
guides is a review of the whole command line and runtime, best done
before a second backend adds to them.

**Done** (closed 2026-10-03): **Peaseblossom 0.1.0 is released** (tag
`v0.1.0`, a GitHub release with the tarball, its signature and the four
systems' packages). The full account - design, every step, what was found
and decided along the way, testing - is in `doc/history/phases/phase-13.md`, under
the same step numbers:

- **1.** Version and identity (`poc -version`, the library manifest's
  version).
- **2.** What a user has to work with: a walk-through, and its fixes
  (`poc <file>`, `-help`, `-c-flag`, error messages that name things).
- **3.** The installed layout and `make install` (`check-install`).
- **4.** The bootstrap seed: building poc without voc (`make seed`,
  `check-seed`).
- **5.** The release tarball (`make dist`, `distcheck`, `dist-sign`).
- **6.** The User's Guide (`doc/users-guide.md`, `doc/examples/`).
- **7.** The Reference Guide (`doc/reference-guide.md`) and `poc(1)`.
- **8.** OS packages (`packaging/`: Fedora, FreeBSD, OpenBSD, pkgsrc).
- **9.** Exit gate, and the 0.1.0 release.

### Phase 14 — Record and array literals, and structured constants

**Added 2026-10-02 (user)**, after Phase 13 and before the VAX/VMS work,
taking record and array literals out of the further extensions (now
Phase 19, where they were candidate 1, from Phase 11 A24). The later
phases moved up by one.

**Goal**: a value of a record or fixed array type written in an
expression, `Point{x := 1, y := 2}` and `Vector{1, 2, 3}`, in the LLVM
backend, with the front end's part shared by the VAX backend later.

**Done** (closed 2026-10-04): literals of named record and fixed array
types (record elements named; array elements positional or indexed,
`[48..57]: 1`), and structured constants, exported through the `.sym`
file. The rules are in `doc/developer/language-extensions.md`, "Record and array
literals"; the design and survey in `doc/developer/record-and-array-literals.md`;
the full account - decisions, every step, what was found, testing - in
`doc/history/phases/phase-14.md`, under the same step numbers:

- **1.** The rules settled in `doc/developer/language-extensions.md`.
- **2.** Front end: the literal node, parsing, checking.
- **3.** Structured constants: folding, selection, the `.sym` file.
- **4.** LLVM backend: entry-block stack slots, private constant globals.
- **5.** Documentation: the User's Guide and the Reference Guide.
- **6.** Exit gate (623ad98, 962c22a; rackhir passed both).

### Phase 15 — VAX/VMS MACRO-32 backend (scoped, deferred, non-executable)

**Goal**: `VaxTypes.Mod`, `VaxCodeGenerator.Mod` and a stub
`VaxToolchainDriver.Mod` emitting MACRO-32 for Phase 8's vertical slice,
each fixture's output reviewed by the user and assembled on the VAX/VMS
development system; linking and running are Phase 16's.

**Done** (closed 2026-10-08): `poc -emit-macro32` writes MACRO-32 for
the slice - integer, `CHAR`, `BOOLEAN` and `SET` values, fixed arrays
and base-less records, strings, the statements, ordinary procedures and
external `"VMS"` ones, the predeclared procedures that need no heap
(`INCL`, `EXCL`, `SHORT`, `LONG` and `ASH` added with the user
2026-10-08), traps, and programs of several modules with their start.
Each of the 35 `vax-` fixtures' `expected-vax.mar` was reviewed by the
user and is assembled on the development system, and 28 also link and
run under the VMS debugger (a widening of "done" decided with the
user). The design and every decision are in
`doc/developer/vax-macro32-backend.md`; the full account - every step,
what was found, the exit review, testing - is in
`doc/history/phases/phase-15.md`, under the design's step numbers:

- **1.** `VaxTypes.Mod`: sizes, offsets and the name scheme.
- **2.** `-emit-macro32`, a module's layout, `tools/vax-assemble`.
- **3.** Straight-line code.
- **4.** Control flow.
- **5.** Procedures and calls; external `"VMS"` procedures.
- **6.** Arrays, records and strings; debugger runs (`tools/vax-run`).
- **7.** The predeclared procedures; 7b, the slice widened.
- **8.** Several modules and the program's start.
- **9.** The phase record and the exit review.

### Phase 16 — Running on VAX/VMS: assemble, link, run, and bootstrap poc there

**Goal**: the MACRO-32 Phase 15 writes is assembled, linked and run on
VAX/VMS 5.5-2, with just enough runtime to compile poc itself, and poc -
built for VAX/VMS - then compiles its own source *on* VAX/VMS: the VMS
counterpart of Phase 10's fixed point.

**Done** (closed 2026-10-12): poc's output assembles, links and runs on
the SIMH VAX - 182 programs of the conformance suite build for the VAX
and print there what they print under the LLVM backend, or what a
reviewed `expected-vax-*` file says - with `rtl/vax`, the runtime poc
needs. poc built for VAX/VMS compiles itself there: V1's, V2's and V3's
31 `.mar` files are identical (`make vax-stages`), and 344 fixtures'
compilations under poc on the guest match the host's
(`make test-vax-guest-poc`). The design and every decision are in
`doc/developer/vax-macro32-backend.md`, sections 13-17; the full account
(every step, what was found, the exit review, what is left open) is in
`doc/history/phases/phase-16.md`:

- **1.** A working VAX/VMS environment and a way to drive it.
- **2.** Assemble, link and run hand-written, then generated, code.
- **3.** Widening the backend to what poc's own source uses.
- **4.** A minimal VAX runtime, `rtl/vax`.
- **5.** Test harness on VMS (`make test-vax`).
- **6.** Bootstrap on VAX/VMS: V1 = V2 = V3; the suite under poc there.
- **7.** The phase record and the exit review.

### Phase 17 — Detailed library/module support for VAX/VMS

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
   change code Phase 16 already emits; how a shareable image exports
   its entry points (transfer vectors, universal symbols, or the linker's
   symbol-vector option, whichever 5.5-2 has), and how a *version* is
   expressed (`GSMATCH` and major/minor identification) so that the layout
   guarantee `.sym` files give importers holds across a rebuild; the same
   31-character symbol limit and Phase 15's mangling, which must now be
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

   **Record** (done, 2026-10-12): the survey of the 5.0 Linker
   and Librarian manuals, checked against the 5.5 and 5.5-2 release
   notes, and eight proposals are in `doc/developer/vax-macro32-backend.md`
   section 18, **approved by the user, 2026-10-12**. Found: 5.5-2 has no symbol
   vector (`UNIVERSAL=` and `.TRANSFER` only), and the build procedures
   are DCL, not MMS, as decided 2026-10-09 (Phase 16 step 1).
   Checked on the guest (section 18.4): a hand-written shareable image in
   poc's sections, reached by `G^` alone, resolves every kind of
   reference; a missing image, a relinked one and a wrong key each give
   a message; `[.VAX-DEC-VMS.OC]` is a usable directory.
   Done (section 18.5): `POC_ADDR`, the constants that hold addresses
   (type descriptors, `PocRtl`'s trap texts) out of `POC_CONST`
   (proposal 5).
   `-library` for the VAX (proposals 1, 2 and 4): `<name>_build.com`
   makes `<NAME>.OLB` and the shareable `<NAME>.EXE` on VMS,
   `<name>_setup.com` defines its logical names, and the runtime is the
   library `POCRTL`, which every other needs; fixture `vax-library`
   builds both on the guest and runs a program linked against each kind.
   Proposal 6 changed as the guest showed (section 18.5). `-build`
   links a program against VAX libraries, their object libraries or,
   with `-shared-libraries`, their shareable images, and `POCRTL`'s
   whenever it is on the library path (`vax-library` runs both on the
   guest). `-install-library` copies a VAX library's files, as text, the
   manifest now listing its parts. On VMS the library path is
   `-library-path`, the search list `POC$LIBRARY` and poc's own
   `[<parent>.LIB.POC]`, joined by `Directories.MakeSubdirectory`, which
   translates a logical name first (run on the guest by V1's poc); the
   import path's logical name is `POC$IMPORT` to match. DCL gives a
   foreign command at most 255 characters of arguments, so poc takes
   `@file` response files (everywhere) and expands `*` and `%` itself
   on VMS (section 18.5). Two exported names with one VAX symbol are
   refused when one or both modules come from a library, recomputed
   from their `.sym` files (proposal 7). On the guest, a missing image,
   an image relinked under an old program and a program compiled against
   another `.sym` each stop with VMS's message (proposal 8). Step 1 is
   complete; next, step 2.

2. **Which existing Oberon libraries and modules to support on VMS.**
   Take Phase 12's complete inventory of voc's modules and Phase 10's
   Oakwood set, and sort each for VAX/VMS: portable as they are; needing a
   VMS platform layer (`Platform`, `Files`, `Modules` - the ones written
   with the four Unix-likes in mind now need a fifth answer); depending on
   IEEE 754 (`Reals`, `MathL`, anything that takes a real apart into
   bits or assumes 64-bit doubles - VAX floating point is different, see
   Phase 16 step 3); depending on the C library, zlib or X11, none of which
   VMS 5.5-2 has by default; or hostile to ODS-2 file names. The output is
   a table of module and verdict, kept as a file the plan names, and the
   decisions.

   **Record** (done, 2026-10-12): the table is
   `doc/research/vms-module-inventory.md`. It covers poc's runtime,
   module by module: what `rtl/vax` has, what the VAX backend makes of
   `rtl/llvm`'s module, and what VMS must supply. It also covers voc's
   129 library modules: 51 need only poc's runtime, 17 take reals apart
   as IEEE, 55 are written for another system, and 6 need C or X11. Six
   proposals, **approved by the user, 2026-10-12**: step 3 is all of
   `rtl/llvm`'s interfaces in `POCRTL`; voc's libraries stay in Phase
   20; reals are converted by poc's own code, not VAXCRTL's; `Files`'
   typed riders write IEEE; `Math`/`MathL` go over `MTH$`; a part-line
   `Out.Flush` reaches a terminal. Next, step 3, starting with `Platform`.

3. **Implementing the chosen Oberon modules on VMS**, into step 1's
   libraries, in dependency order, each with fixtures shared with the LLVM
   side where the module is the same (the same `.mod` and `expected`, run
   on both), and VAX-specific fixtures where the behavior differs on
   purpose, documented where it differs.

   **Record** (in progress): `Platform` is done (2026-10-12): its eight
   proposals, **approved by the user, 2026-10-12**, are
   `doc/developer/vax-macro32-backend.md` section 19.1, and section 19.2
   records the work. It has voc's whole interface, over 18 new routines
   in `PocRtl.mar`. Fixture `vax-platform-files` runs 70 checks on the
   guest. `Files` is done (2026-10-12): its nine proposals, **approved by
   the user, 2026-10-12**, are section 19.3, and section 19.4 records the
   work. It has the whole interface, and its typed riders write IEEE
   reals. Fixtures `vax-files-riders` (`llvm-files-riders`' programs on
   the guest) and `vax-files-extra` (75 checks) are new. `Modules` is
   done (2026-10-13): its eight proposals, **approved by the user,
   2026-10-13**, are section 19.5, and section 19.6 records the work. It
   has the whole interface but `Init`. The VAX backend writes each
   module's descriptor in a program that contains `Modules`. Fixtures
   `vax-modules-commands` (`llvm-modules-commands`' programs) and
   `vax-modules-extra` are new. `RealDigits` and `Reals` are done
   (2026-10-13): their six proposals, **approved by the user,
   2026-10-13**, are section 19.7, and section 19.8 records the work.
   They come with a new `DecimalToReal` (correctly rounded decimal to F
   and G), `FormattedText` for the VAX, and `Out`'s and `Err`'s `Real`,
   `LongReal`, `Ten` and `IsConsole`. Fixtures `vax-real-digits`,
   `vax-reals-module` and `vax-out-reals` are new. `FormattedOutput` and
   `OutStr` are done (2026-10-13): their five proposals, **approved by
   the user, 2026-10-13**, are section 19.9, and section 19.10 records
   the work. `Out` and `Err` now format through `FormattedOutput`, as on
   LLVM, and `OutStr` is `rtl/llvm`'s. Fixture `vax-outstr` is new. `In`,
   `InStr` and `FormattedInput` are done (2026-10-13): their five
   proposals, **approved by the user, 2026-10-13**, are section 19.11, and
   section 19.12 records the work. `In` reads SYS$INPUT through
   `Platform`, which gives `Out`'s unfinished line as the prompt on a
   terminal, and reals are read by `DecimalToReal`. Fixtures `vax-in`,
   `vax-in-extra` and `vax-instr` are new. `Strings` is done
   (2026-10-13): its three proposals, **approved by the user,
   2026-10-13**, are section 19.13, and section 19.14 records the work.
   Its reals are read by `DecimalToReal`. Fixture `vax-strings-module` is
   new. `Math` and `MathL` are done (2026-10-14): their five proposals,
   **approved by the user, 2026-10-14**, are section 19.15, and section
   19.16 records the work. They call `MTH$` and `OTS$` through a new
   `PocRtl` routine, `POC_MATH`, which returns a signalled condition as a
   status. Fixtures `vax-math-module` and `vax-math-extra` are new.
   `Args` and `VT100` are done (2026-10-14): their four proposals,
   **approved by the user, 2026-10-14**, are section 19.17, and section
   19.18 records the work. `Out.Flush` writes a part line to a terminal
   without ending it, and `VT100` flushes each sequence. Fixtures
   `vax-args` and `vax-vt100` are new. `Texts` and `Oberon` are done
   (2026-10-14): their four proposals, **approved by the user,
   2026-10-14** (no `.Bak`, and no `HOME` or `USER`), are section 19.19,
   and section 19.20 records the work. `Texts` scans reals by
   `DecimalToReal` and keeps the old file as an older version, `Oberon`
   is `rtl/llvm`'s, and `Platform.getEnv` falls back to a DCL symbol.
   `Files.New("")` was fixed on the way. Fixtures `vax-texts` and
   `vax-oberon` are new. That is the last of the inventory's ten
   groups: every module of `rtl/llvm` has its VAX version, but for the
   internal `ModuleTable` and `FileDescriptorOutput`, whose work
   `PocRtl`'s `POC_ROOTS` and `LineOutput` do.

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

   **Done (2026-10-14)**: `doc/research/vms-native-library-inventory.md`,
   seven proposals, **approved by the user, 2026-10-14**. Every one of
   `STARLETSD.TLB`'s 65 SDL modules is generated in step 5. A smaller
   tier gets fixtures on the guest: the synchronous system services
   listed there, RMS's relative and indexed files, parts of `LIB$`,
   `SMG$`, `SOR$`, and `STR$`'s decimal arithmetic. Three hand-written
   modules (`Conditions`, `LogicalNames`, `Symbols`) and a hand-declared
   `CLI$` complete it. The privileged and vector services, DECdtm,
   DECdns, DECthreads, `PPL$`, `DTK$`, D and H floating, and the
   utilities without SDL routines other than `CLI$` are left out, each
   for a reason the file records.

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

   **First look** (2026-10-11, `doc/developer/vms-sdl-interfaces.md`):
   UNSDL is a set of SDL back ends that `SDL/NOPARSE` calls with the
   parsed tree of one of `STARLETSD.TLB`'s 65 modules, and a verb of its
   own (`unsdl.cld`) that runs `SDL/NOPARSE`; the guest has the library,
   `SDLNPARSE.EXE` and the `SDL` verb, so it runs there as it is. **Decided by the user
   the same day**: the generator, a back end of its own, runs on the VAX
   and is built with VAX C; the `.SDI` files are not read on the host.

   **Part 1, the mechanisms (2026-10-14)**: eight proposals in
   `vms-sdl-interfaces.md`, **approved by the user, 2026-10-14**, and
   implemented the same day (its "Part 1 done"). In a `["VMS"]`
   declaration the formal says the mechanism: a value parameter of a
   longword or less by value, a wider one an error; `VAR` and `x-` by
   reference; an open `ARRAY OF CHAR` by a `CLASS_S` descriptor the
   caller builds; `NIL` an omitted argument; a procedure-typed parameter
   checked to be one VMS can call. `rtl/vax/VmsArguments.Mod` has the
   descriptor, item list and I/O status block types. Fixtures
   `vax-vms-calls` (real routines on the guest), `vax-vms-arguments`,
   `semantic-vms-arguments`, `semantic-reject-vms-arguments`.

   **Part 2, the generator (2026-10-14)**: eight proposals, **approved by
   the user, 2026-10-14**, after `SDLDUMP` showed 5.5-2's trees; made the
   same day (`vms-sdl-interfaces.md`, "Part 2 so far"). `tools/sdloberon`,
   an SDL back end in VAX C that `tools/vax-sdl` builds and runs on the
   guest (from `SYS$SHARE`, where the user copies it), writes one Oberon
   module for each SDL `MODULE` node into `rtl/vax/vms`, the library
   `VMSDEF`; in a `["VMS"]` declaration an `x-` `ARRAY OF SYSTEM.BYTE`
   takes any actual. The constants agree with `STARLET.MLB`'s, 3587 names;
   poc's layout of every record type with SDL's. Fixture `vax-vmsdef`.
   The first seven library modules are generated and were **approved by
   the user, 2026-10-15**, with a quadword in declared `x-: HUGEINT`;
   the other 58 were generated the same day ("Part 2 finished"): 243
   Oberon modules from all 65, leaving out DECthreads and `MTH$`'s D, H
   and complex entries. `STARLET.MLB` agrees on 17,559 names of 186
   modules, none differing in value; poc's layout of 225 record types
   agrees with SDL's. On the way: SDL's `ORIGIN`, `SMBMSG`'s module
   renamed `SMBMSGDEF`, and a VAX library's shareable image linked from
   its `.OLB` by `/INCLUDE` (`vax-macro32-backend.md`, section 18.5).

   **Part 3, SDL's unsigned types (2026-10-14)**: seven proposals,
   **approved by the user, 2026-10-14**, and made the same day
   (`vms-sdl-interfaces.md`, "Part 3 done"): an unsigned field or
   parameter is the CARD of its width, and `VmsArguments`' lengths are
   `CARD16`.

   **Part 4, the hand-written modules (2026-10-15)**: seven proposals,
   **approved by the user, 2026-10-15**, and made the same day
   (`vms-sdl-interfaces.md`, "Part 4 done"): `Conditions`,
   `LogicalNames` and `Symbols` in `rtl/vax/vmslib`, the library
   `VMSLIB`, which needs `VMSDEF` and `POCRTL`. Fixture `vax-vmslib`
   runs them on the guest.

   **Part 5, `CLI$` (2026-10-15)**: nine proposals in
   `vax-macro32-backend.md`, section 23, **approved by the user,
   2026-10-15**; the guest's answers are in its 23.4. They cover a `CommandLanguage` module in `VMSLIB` with a
   MACRO-32 part; the table found by a weak reference to
   `POC$COMMAND_TABLE`; dispatch on `$VERB` instead of `CLI$DISPATCH`;
   `-build` taking a `.cld` file; five checks on the guest first; and
   fixtures `vax-cli-verb` and `vax-cli-table`. **Built 2026-10-15**
   (section 23.5), with two changes from the proposals. First, the program
   passes its table's address (the user's choice): the table's symbol is
   declared as an external procedure, and `SYSTEM.VAL(SYSTEM.ADDRESS, T)`
   gives the address, so the module has no MACRO-32 part and works with a
   shared `VMSLIB`. Second, five interface changes were approved by the
   user (`Presence`, more constants, `NoTable` for 0, `Truncated`, any
   number of `.cld` files). `-build` takes `.cld` files (fixture
   `vax-build-command-tables`). `vax-cli-verb` and `vax-cli-table` pass on
   the guest, and the User's Guide's chapter 12 example was run there.

   **Part 6, argument lists through `LIB$CALLG` (2026-10-15)**: five
   proposals in `vms-sdl-interfaces.md`, part 5, **approved by the user,
   2026-10-15**. They are made after "Ongoing language enhancements" item
   3 is merged from `main` with its VAX half. A guest test first compares
   `LIB$SIGNAL` called directly and through `LIB$CALLG`. Then
   `Conditions.SignalList` and `StopList` take a whole argument list:
   several FAO arguments, or chained conditions. The guest test was run
   the same day (part 5, "tried on the guest"): only the PC, the depth
   and a Continue's R0 differ, so proposal 2 stands. `SignalList` and
   `StopList` built the same day ("Part 5 done"); fixture `vax-vmslib`
   runs them.

   **Part 7, RMS's indexed and relative files (2026-10-15)**: six
   proposals in `vms-sdl-interfaces.md`, part 6, **approved by the user,
   2026-10-15**, the first supported-tier group. There is no module: fixture
   `vax-rms-indexed` uses `STARLET` and the `FAB`, `RAB` and `XABKEY` records
   directly, with the XAB header set by `SYSTEM.PUT`. It passes on the
   guest, which showed that two streams in one process lock each other out
   and that duplicates come back in the order they were put ("Part 6
   done").

   **Part 8, `SMG$` screen management (2026-10-16)**: seven proposals in
   `vms-sdl-interfaces.md`, part 7, **approved by the user, 2026-10-16**.
   There is no module: fixture `vax-smg` draws on a pasteboard on a file
   and captures it by `SMG$SNAPSHOT`, and reads a keyboard on a file;
   `SmgScreen` does the same on a terminal, checked by hand. A menu's
   choices are a `CLASS_A` descriptor, which the generator now leaves to
   the program (`VmsArguments.DescribeArray`). The guest showed that a
   pasteboard on a file is 66 by 132, and that a menu is chosen only on a
   terminal ("Part 7 done").

   **Part 9, `SOR$` sorting and merging (2026-10-16)**: eight proposals in
   `vms-sdl-interfaces.md`, part 8, **approved by the user, 2026-10-16**.
   VMSLIB gains `SortMerge`, the constants `SORTSHR` defines and no SDL
   module has, checked against the linker. Fixture `vax-sort` sorts files
   and records, merges, calls a comparison routine of the program's, and
   releases binary records through a descriptor of the program's. The guest
   showed that SORT keeps `Files`' Stream_LF format and that
   `noDuplicates` does not keep the first record ("Part 8 done").

   **Part 10, `STR$`'s decimal arithmetic (2026-10-16)**: eight proposals
   in `vms-sdl-interfaces.md`, part 9, **approved by the user,
   2026-10-16**. VMSLIB gains `DecimalStrings`: numbers of up to 255
   digits, the five routines' arithmetic with their signals returned as
   statuses through `LIB$SIG_TO_RET`, and conversions to and from text.
   Fixture `vax-decimal-strings`. The guest showed that `STR$` writes a
   result right-justified with zeros, that `STR$ROUND`'s places are
   significant digits, and that after `STR$_TRU` a result is not its value
   ("Part 9 done").

   **Part 11, the rest of `LIB$` (2026-10-16)**: eight proposals in
   `vms-sdl-interfaces.md`, part 10, **approved by the user,
   2026-10-16**, with process control a part of its own still to come.
   VMSLIB gains `DateTimes` and `BalancedTrees`, whose nodes are the
   program's records, extended from `LIB$`'s node header, so the collector
   traces them. Fixtures `vax-date-times`, `vax-balanced-trees`,
   `vax-lib-information` (with `LIB$GETQUI`, added by the user's
   amendment) and `vax-interlocked`. The guest showed that
   `LIB$TRAVERSE_TREE` stops at an action's failure, that a refused
   duplicate is never allocated, that `JPI$_USERNAME` comes back
   blank-padded, and that an empty queue gives the header's address
   ("Part 10 done"; `vax-macro32-backend.md`, section 22.8).

   **Part 12, process control (2026-10-16)**: eight proposals in
   `vms-sdl-interfaces.md`, part 11, **approved by the user,
   2026-10-16**. VMSLIB gains `Subprocesses`: `Run` and `Start`, and a
   started subprocess kept alive until `Wait` sees it end, since VMS
   writes its status later. Fixture `vax-subprocesses` also chains two
   programs by `LIB$RUN_PROGRAM` and `LIB$DO_COMMAND`. The guest showed
   that `Wait` gives `SS$_NORMAL` after `Stop`, that a procedure goes on
   after `LIB$DO_COMMAND`'s command, and that a process name has at most
   15 characters, which the fixture's first version broke and hung on
   ("Part 11 done"; `vax-macro32-backend.md`, section 22.9). `LIB$ATTACH`
   is still to be checked by hand.

   **Part 13, the synchronous system services (2026-10-16)**: seven
   proposals in `vms-sdl-interfaces.md`, part 12, **approved by the user,
   2026-10-16**, the first gap of step 8's plan. Fixture
   `vax-system-services` calls `$GETSYIW`, `$GETDVIW`, `$NUMTIM`, `$FAO`
   and `$FAOL`, `$ENQW` and `$DEQ`, `$WAKE`, `$SETPRN` and a mailbox's
   `$CREMBX`, `$QIOW` and `$DASSGN` through `STARLET`; `VmsArguments`
   gains `LockStatusBlock`. All passed on the first run. The guest showed
   that a new resource's value block is valid and zero, that VMS keeps
   no count of wakes, and that it is a `VAXserver 3900` ("Part 12
   done").

6. **Asynchronous system traps and other asynchrony.** VMS systems
   programming leans on them: a service such as `$QIO`, `$SETIMR` or `$ENQ`
   is asked to *complete* asynchronously and to call a routine (an AST)
   when it does, at any point in the program, on the program's own stack,
   with `$SETAST` to enable or disable delivery and `$DCLAST` to queue one.
   What that demands of poc is the point of the step, and it has to be
   worked out and not guessed: (a) an AST routine is an Oberon procedure
   called *by VMS*, with an argument the program chose, so a procedure
   value (Phase 9 step 8) must be callable under the VMS Calling Standard -
   the strongest argument for one calling convention throughout (Phase 16
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
   (`$DCLEXH`) and the runtime's own traps (Phase 16 step 3c), which are
   asynchronous in the same sense. The result is a design written into
   this plan, an Oberon-level `VMS` module (or modules) that exposes it
   ($QIO with a completion AST, timers, mailboxes, event flags, condition
   handlers), and fixtures on the guest that fire ASTs while the main
   program allocates heavily - so that the collector's interaction with
   them is tested where it would fail - and that fail if the AST
   delivery rules are wrong.

   **Proposals (2026-10-15)**: nine, in `vax-macro32-backend.md`,
   section 22, from the 5.x manuals and the runtime as it is;
   **approved by the user, 2026-10-15**. In short: an AST routine is a global Oberon
   procedure of type `AsynchronousTraps.Routine`, the calling convention
   needing no adapter; the heap runs with ASTs disabled once a program
   can have them; the rest of the runtime is a documented rule;
   `AsynchronousTraps`, `EventFlags`, `Timers`, `ExitHandlers` and
   handlers in `Conditions`; four questions tried on the guest first.
   **Built 2026-10-15** (section 22.6): the modules, the generator's
   typed AST routines, CTRL/C by `Platform.SetInterruptHandler` (tried by
   hand), and fixtures `vax-asts`, `vax-asts-heap` and
   `vax-conditions-handlers`. Two departures: a handler's arrays are fixed
   arrays, since a `VAR` record takes a hidden tag, and `Timers.After`
   takes no request argument. Also found: a `$EXIT` from an exit handler
   skips the rest, poc's own included.
   **Approved 2026-10-15** (section 22.7): trap 15
   when an AST re-enters the heap in a program that does not import
   `AsynchronousTraps`, so that breaking that rule fails at once, with a
   message, instead of corrupting the heap.

7. **Distributing poc on VAX/VMS.** A release has to give a VMS site
   poc and its libraries. Nine proposals were written 2026-10-15 and
   **approved by the user, 2026-10-15**. The full text is in
   `vax-macro32-backend.md`, section 21.
   - The kit is all text, since an FTP binary copy lands as fixed
     512-byte records. It is made on the host by `make vax-kit` and holds:
     - poc's V1 `.mar` files;
     - `POCRTL`, `VMSDEF` and `VMSLIB`, as `-library` writes them for
       `-O2` and `-OC`;
     - poc's source.
   - It is one self-unpacking DCL procedure, `POC-<version>.COM`, with a
     `CREATE` and a `DECK/DOLLARS` for each file.
   - `BUILD.COM` assembles and links `POC.EXE` into `[.BIN]` and builds
     the libraries into `[.LIB.POC]`, where poc finds them by itself.
     `SETUP.COM` defines the `POC` command and one size model's library
     names.
   - `make dist` puts the kit in the tarball as `vax/`, and the GitHub
     release carries it as an asset, once `vax` is merged.
   - **The packages, once `vax` is merged** (decided with the user,
     2026-10-16). Few want VAX/VMS, so it is an optional package, not a
     second compiler:
     - The Unix packages keep one `poc`, with the VAX code generator built
       in. It is about a quarter of poc's objects (0.65 of 2.8 MB) and
       needs no tool on Unix.
     - What the VAX target needs besides goes in an optional
       `peaseblossom-vax` package, or `make install-vax` from source:
       `rtl/vax` (2.8 MB, VMSDEF's 65 modules 2.3 MB of it), VMSLIB, the
       kit, and **a VAX/VMS guide of its own**, apart from the User's and
       Reference Guides (the user). `doc/vax-vms-guide.md`, its outline
       reviewed 2026-10-16: the front matter and chapters 1-5 and 7 are
       written and reviewed, their programs in `doc/examples/vax`
       (2026-10-16). Chapters 6 and 8-17, the appendices, and its checks
       (`doc-vax-guide`, `make doc`, `install-vax`, the kit's text copy)
       are to come. The User's Guide's chapter 12 shrinks to a pointer
       once chapter 10 has taken its `GREET` example.
     - Without that package, `poc -target vax-dec-vms` says that the VAX
       runtime is not installed and which package has it.
   - `make check-vax-kit` installs it on the guest and builds programs
     with it; with `-full` it also checks the fixed point.
   - poc for VMS leaves the LLVM back end out, which settles that open
     design question.
     - The module list and the method slots move to the front end.
     - `Poc.Mod`'s LLVM work moves into `LLVMBackEnd`. A second module
       of that name, in `src/driver/no-llvm`, refuses every LLVM option,
       and the import path decides which one a build gets.
     - V1's `.mar` loses about 1.48 MB of its 5.4 MB.
   - A tenth proposal, asked for and approved by the user the same day,
     splits the kit in two: `POC-<version>.COM`, poc and `POCRTL`, and
     `POC-VMS-<version>.COM`, `VMSDEF` and `VMSLIB`, unpacked into the
     same top at once or later. `@BUILD` builds what is not built yet.

8. **Exit gate.** Every module and interface chosen builds into both
   library kinds and passes its fixtures on the guest, the AST fixtures
   pass repeatedly (asynchrony makes a single pass weak evidence), the
   whole VAX conformance suite from Phase 16 is still clean, and step 7's
   kits install and pass `make check-vax-kit` on the guest.

   **Plan, approved by the user, 2026-10-16.** Reading the tree against
   that text found four gaps, closed in this order, each committed on its
   own:
   - **Done (part 13).** **The supported tier's system services**
     without a fixture on the guest: `$GETSYIW`, `$GETDVIW`, `$NUMTIM`, `$FAO` (only `$FAOL` is
     tried), `$ENQW` and `$DEQ`, `$WAKE` and `$SETPRN`. A part 13 of step
     5, proposals first, with one fixture, `vax-system-services`, and no
     module.
   - **Done.** **VMSLIB from its shareable image.** Every library build
     makes both kinds, but every VMSLIB fixture linked against the object
     libraries, and a shareable image has its own copy of the writable
     data that `Subprocesses`, `ExitHandlers`, `AsynchronousTraps` and
     `BalancedTrees` keep. Fixture `vax-vmslib-shareable`: one program
     using every VMSLIB module, its subprocess and exit handler reachable
     only from VMSLIB's lists across two collections, linked both ways
     under `-O2` and `-OC`; all four runs print the same.
   - **Done.** **The AST fixtures, repeatedly.** `vax_do` takes `VAX_REPEAT=<n>`:
     a fixture that honours it builds once on the guest and runs each
     program n times, compares each later run with the first there
     (`DIFFERENCES`), and prints only a difference, so its
     `guest-run.expected` is unchanged. `make test-vax-asts` (default 20)
     runs `vax-asts`, `vax-asts-heap`, `vax-conditions-handlers` and
     `vax-subprocesses` so; not part of `make check`. `tools/vax-do -p`
     gives the procedure its P1, and the procedure calls itself with
     `/OUTPUT` for each run (`DEVELOPER.md`, section 4). `vax-asts-heap`
     now builds `AstNoImport` before its runs, which moved one line of its
     `guest-run.expected`.
   - **Done.** **The kits.** `make vax-kit` takes VMSLIB by a glob, but
     the kit's `README.TXT` and `README-VMS.TXT` named six of its
     modules, now twelve, and `KitVmsLib` used `Conditions` alone. Both
     READMEs now name all twelve, `README-VMS.TXT` with a line on what
     each covers, and `KitVmsLib` uses every VMSLIB module and prints a
     line for each, which `check-vax-kit` expects.

   Before them, part 12 finished and `LIB$ATTACH` checked by hand (done
   2026-10-16; `vms-sdl-interfaces.md`, "Part 11 done"). Then
   the gate's run: `make check` on the four hosts, `make test-vax-asts`,
   `make test-vax`, `make test-vax-guest-poc`, `make check-vax-kit
   CHECK_VAX_KIT_FLAGS=-full`, and rackhir on the pushed commit.

**Testing summary**: steps 1, 3, 5 and 6 are fixtures run on the guest;
steps 2 and 4 are decisions with written artifacts, verified against the
manuals they cite; step 7 is checked by `make check-vax-kit` on the
guest; step 8 is the gate.

### Phase 18 — Direct VAX/VMS object files (no MACRO-32 in the loop)

**Goal**: `poc` writes VAX/VMS object modules (`.OBJ`) itself, so a
compile is Oberon source to object file and `LINK` is the only VMS tool
left in the build - the assembler (`MACRO`) drops out. Phases 15-17 emit
MACRO-32 text and hand it to the assembler; that stays as `-emit-mar`, the
human-readable form the earlier phases reviewed and a debugging aid (and
the oracle this phase tests against), but it stops being the path a normal
build takes. Reasons to do it, to be checked and not assumed: the
assembler is one less tool that has to be present and fast on the guest
(Phase 16 step 1 confirms from the 5.5-2 SPD what the base kit contains);
a compile that produces its object directly does one pass over the code
instead of two; and poc controls exactly what goes into the object, the
debug and traceback information included.

**Explicit non-goals**: writing executable *images* (`LINK` stays - it
also builds shareable images, applies the option file, and is what
Phase 17's libraries rely on); writing object *libraries* (`LIBRARY`
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
   31-character symbol length again - Phase 15's mangling is unchanged),
   and the on-disk form (an object file is a record-oriented RMS file, so a
   file merely copied from another system's byte stream is *not* an object
   the linker accepts until its record attributes are set; `FDL` and
   `CONVERT` are the guest-side tools, and `Files` on VMS (Phase 16 step 4)
   is what lets poc write records directly). Read real objects first: what
   `MACRO` produces for each of the Phase 15 fixtures, dumped with
   `ANALYZE/OBJECT` and in hex, is the ground truth the specification is
   checked against.

2. **An instruction-level representation under the code generator.**
   `VaxCodeGenerator.Mod` today writes MACRO-32 text as it walks the tree.
   To write bytes the same decisions must be available as data: a
   `VaxInstruction` representation (opcode, operand specifiers with
   addressing mode, register, displacement and symbol, labels, directives)
   built once, and two consumers of it - the existing text printer, which
   must produce exactly the `.mar` the Phase 15 fixtures already hold, and
   the new encoder. The refactor is done first and on its own, with the
   `expected-vax.mar` fixtures (and the runnable Phase 16 ones) as the
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
   constants in the format Phase 16 step 3 chose). **Testing**: byte-for-
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
   routines), and the end record. Phase 17's requirements ride on it:
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
   with `-emit-mar` keeping the Phase 15 behavior) writes `<module>.OBJ`;
   `VaxToolchainDriver.Mod` stops invoking `MACRO`. Every earlier phase's
   VAX fixtures run in both modes - built through `.mar` and `MACRO`, and
   built directly - and give the same output; Phase 17's object libraries
   (`LIBRARY/CREATE` of poc's `.OBJ` files) and shareable images
   (`LINK/SHAREABLE`) work with the direct objects unchanged, and are tested
   that way.

7. **Bootstrap again, and the exit gate.** Rebuild poc for VAX/VMS with
   the direct writer, on the guest: the V1/V2/V3 fixed point of Phase 16
   step 6, now over `.OBJ` files - an object compiled by the poc built from
   the previous stage must be byte-identical to the one the stage before
   produced from the same source (modulo the module header's timestamp
   and the file's creation attributes, which the specification lists). The
   whole VAX conformance suite passes with objects written directly, and
   the whole Phase 17 suite, ASTs included; the run that builds poc must
   involve no `MACRO`.

**Testing summary**: steps 2 and 3 are byte-level comparisons against the
existing text path and against the assembler; steps 4 and 6 are
`ANALYZE/OBJECT` comparisons plus link-and-run; step 7's fixed point
over object files is the gate.

### Phase 19 — Further extensions to Oberon-2

**Goal**: settle the language extensions that are larger than Phase 11's -
each a design of its own, through the front end, the `.sym` format and both
backends - and implement the ones adopted. As in Phase 11, each starts with
a survey of what other Oberons do (and Modula-2/-3 where they are the only
precedent) and ends with the user's decision; "not adopted" is a legitimate
result, recorded in `doc/developer/language-extensions.md` like the others.

**Candidates** (from `000-todo.org`'s Extensions list and Phase 11's
inventory):

Record and array literals, candidate 1 here until 2026-10-02 (Phase 11
A24, moved here 2026-09-26), are Phase 14 now.

1. **Slices of one-dimensional arrays** (`000-todo.org`).
2. *voc's read-only parameters, `x-`*, were candidate 2 here until
   2026-10-05, when they were adopted and moved to "Ongoing language
   enhancements", to be done now.
3. **The terminator-based `ARRAY OF CHAR` assignment rule** (`000-todo.org`;
   decided against in Phase 11 A21, to reconsider).
4. **`QUOT(x, y)` and `REM(x, y)`**, truncated integer division and its
   remainder (the user, 2026-10-05): Ada's `/` and `rem`, C's `/` and `%`,
   beside the floor `DIV` and `MOD`, as predeclared function procedures
   rather than operators, so that no program's own `REM` breaks.
   `doc/developer/language-extensions.md`, "QUOT and REM", has the
   extension; its survey (`doc/research/truncating-division-survey.md`,
   done 2026-10-05) found no Oberon with it, ISO Modula-2's `/` and `REM`
   the one precedent, and Modula-3 with only the floor pair. **Adopted**
   by the user 2026-10-05, as `QUOT` and `REM`, the two together (`REM` is
   no use without `QUOT`), to be implemented at some point; not built
   yet.
5. **Unsigned integer types** (the user, 2026-10-06, after the FLTK
   binding declared C's unsigned types as the signed `SYSTEM.INT8` to
   `SYSTEM.INT64` of the same width, which pass the bits but compare,
   divide and widen as signed). Leaning, with the user: in SYSTEM, as
   `SYSTEM.UINT8`, `UINT16`, `UINT32` and `UINT64`, beside the signed
   fixed-width types already there for C, and outside the inclusion
   chain `SHORTINT ⊆ INTEGER ⊆ LONGINT ⊆ HUGEINT`, which they do not fit
   (`UINT32` is not within `INT32`, and no signed type holds `UINT64`).
   To settle: which mixtures with signed types are allowed without a
   conversion (only those that lose no value, such as `UINT8` to
   `INTEGER`?) and which conversions are written how; arithmetic modulo
   2^n, with unsigned comparison, `DIV` and `MOD` (LLVM's `udiv`,
   `urem`, `icmp ult`; the VAX's unsigned branches); `UINT64`'s
   constants above `MAX(HUGEINT)`, its `MAX` and `MIN`, and printing it
   (`Out`, `OutStr`); and `-strict`. Wrapping means on overflow and
   underflow both (the user, 2026-10-08). The survey,
   `doc/research/unsigned-survey.md` (done 2026-10-08), found two
   placements with precedent: a family of their own, apart from the
   signed types (the Oakwood Guidelines' recommendation, XDS's
   `SYSTEM.CARD8` to `CARD32`, GNU Modula-2's expression rule), and
   Active Oberon's single chain, in which a signed value goes into an
   unsigned type of its size without a conversion. Oberon-07 and Oberon+
   have only an unsigned `BYTE`, Component Pascal none, and Modula-3 and
   Oberon System 3's `BIT` give unsigned operations on signed types as
   procedures. **Adopted** by the user 2026-10-08:
   `doc/developer/language-extensions.md`, "Unsigned integer types", has
   the extension - `SYSTEM.CARD8`, `CARD16`, `CARD32` and `CARD64`, a
   family apart from the signed integers and included in the reals;
   `SYSTEM.VAL` the only conversion between the families, `SHORT` and
   `LONG` within it; unary minus allowed; values above `MAX(HUGEINT)`
   as hexadecimal patterns, not decimal literals; `FOR` counting down by
   subtraction. With it, every `FOR`, signed ones included, ends before
   a step that would pass its final value (`language-extensions.md`,
   "FOR final value"), so that a CARD counted down to 0, or any loop up
   to `MAX(T)`, ends. `SYSTEM.ADDRESS` stays signed (decided the same
   day; "Open design questions", below). With it, **`SYSTEM.CARD`**
   (decided with the user the same day): an unsigned type as wide as
   `ADDRESS` (the machine word, on every target poc has), for C's
   `size_t` and `uintptr_t`, unsigned address comparisons (the
   collector's `MIN(SYSTEM.ADDRESS)` bias) and VAX system-space
   addresses, which start at 80000000H. A type of its own, as `ADDRESS`
   is, not an alias of `CARD32` or `CARD64`, so that a program passing it
   as a `VAR` parameter does not compile on one width and fail on the
   other; it and the `CARDn` of its width include each other, and it is
   otherwise a member of the CARD family (`SYSTEM.VAL` to and from
   `ADDRESS`). No signed counterpart: `ADDRESS` is the signed word-sized
   type, under that name only (the user). **Implemented 2026-10-14** for
   the LLVM backend, with the new end of every `FOR` loop and the text
   procedures `Card` and `CardHex` (`Out`, `Err`, `OutStr`) and `Card`
   (`In`, `InStr`), named with the user that day; what was settled while
   building it, and the fixtures, are in `language-extensions.md`,
   "Unsigned integer types". The VAX backend's part follows on the `vax`
   branch (Phase 17). **Done for the VAX on 2026-10-14**, on the `vax`
   branch. That includes the new `FOR` end, the runtime's `Card`
   procedures, and `POC_CDIV`, `POC_CMOD` and `POC_CTOG`. The record is
   `vax-macro32-backend.md` section 20; `sdloberon`'s `CARDn` follows.

**Exit gate**: every candidate has a recorded decision; each adopted one has
fixtures, is rejected by `-strict`, and passes `make check` on Linux and the
three BSDs (and, once Phase 16 exists, on VAX/VMS).

### Phase 20 — voc's library modules

**Goal**: decide which of the modules under voc's `src/library` poc
offers, and build those. Moved here from Phase 12 step 4 (user,
2026-09-27): Phase 12 makes poc compatible with voc's runtime modules
only, and the libraries wait until everything else is done.

**Starting point**: Phase 12 step 3's inventory,
`doc/research/voc-module-inventory.md` (regenerated by `tools/voc-inventory/
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

## Peaseblossom 0.6.0

What `main` had gained since 0.5.0 was released as **Peaseblossom 0.6.0**
on 2026-10-14: the unsigned integer types `SYSTEM.CARD8`..`CARD64` and
`SYSTEM.CARD`, with `Card`/`CardHex` in `Out`, `Err` and `OutStr` and
`Card` in `In` and `InStr` (`ff457c2`); every `FOR` loop ending before a
step past its final value (the same commit); `make doc-all` (`03e346e`);
and three fixes (`482375e`, `63f53c1` with `c398467`, `a9938d6`). The
RPM's `%changelog` lists them. It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `0627d7b` by `make set-version`, after
  `tools/check-hosts -t check-install -t check-seed` passed on atla,
  cymoril, artos and alerik (358 fixtures at each stage). rackhir passed
  `0627d7b`.
- **The tarball** came from `make distcheck` (SHA-256 `b75772ed...`,
  5047826 bytes). It is signed, with the signed tag `v0.6.0`, and
  published as a GitHub release.
- **Each package** was made from the published tarball (`makesum`; the
  `distinfo` files are committed after the release), then built and
  checked on its system: FreeBSD amd64 (alerik) and arm64 (rackhir),
  OpenBSD i386 (cymoril) and amd64 (jherek), NetBSD amd64 (artos) and
  i386 (yishana); `check.sh` on the stage, check-plist, portlint and
  pkglint clean, packing lists unchanged. Each was installed as root over
  0.5.0, checked with `check.sh` against the installed poc, removed with
  nothing of its packing list left, and installed again. `mock` built and
  checked the RPM, and on atla 0.6.0 replaces 0.5.0.
- **Clock skew.** cymoril's and jherek's OpenBSD `ntpd` trusted the QEMU
  `pvclock0` sensor, 32 minutes off after a host suspend, and the first
  builds there and on artos warned of clock skew. With the user, `sensor
  *` was commented out on both OpenBSD hosts, artos's clock was stepped
  with `ntpdate`, and the three packages were rebuilt with no warning.
- **OpenBSD's `pkg_add -u`** takes package names, not files: given a
  path it says "Problem finding" and exits 0. A newer package file given
  without `-u` updates the installed one.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` and attached to the release; every file was
  downloaded again and checked against `SHA256SUMS` and the signatures.

## Ongoing bug fixing

Bugs found outside a phase's own work - by using poc on other programs -
fixed as they come, alongside whichever phase is current. Each item says
where it was found, and is marked `[fixed]` once its fix, with a
fixture, is committed (`git log -S` on the item finds the commit); a fixed
item stays until the next phase's close-out, which moves it to that
phase's record.

The four found porting olibfyaml to poc (`~/Repos/Oberon/polibfyaml`),
fixed in 526d7ba, are in `doc/history/phases/phase-14.md`.

Those fixed while Phase 15 was current, 1-6, are in
`doc/history/phases/phase-15.md`.

Those fixed while Phase 16 was current, 7, are in
`doc/history/phases/phase-16.md`.

## Ongoing library enhancements

Additions to the runtime library (`rtl/llvm`) that using poc on other
programs shows are wanted, made as they come, alongside whichever phase
is current. Each item says where the need was found, and is marked
`[done]` once it is committed with its fixtures, its `rtl/llvm/README.md`
entry and the Reference Guide regenerated (`tools/rtl-reference
update`); a done item stays until the next phase's close-out, which
moves it to that phase's record.

Those done while Phase 15 was current, 1 and 2, are in
`doc/history/phases/phase-15.md`.

3.  OutStr should have versions of the appropriate procedures that
    take a parameter `VAR pos: LONGINT` so the routines don't have to
    keep iterating over the earlier elements of the strings.  Those
    procedures would first check that `pos` points to the null
    character that ends the string. If it does, it inserts there.  If
    it doesn't, it moves forward to where that string ends and then
    inserts.  When the procedures return, `pos` points to the position
    of the new end-of-string null character.

## Ongoing language enhancements

Language extensions that using poc on other programs shows are wanted,
made as they come, alongside whichever phase is current, rather than
waiting for Phase 19. Each is decided with the user and written up in
`doc/developer/language-extensions.md` first. An item is marked `[done]` once it is
committed with its fixtures, `-strict` rejects it, `make check` passes on
Linux and the three BSDs, and the User's and Reference Guides say what it
is; a done item stays until the next phase's close-out, which moves it to
that phase's record.

Those done while Phase 15 was current, 1 and 2, are in
`doc/history/phases/phase-15.md`.

3. **[done] An external procedure's address, by `SYSTEM.VAL`** (proposed
   2026-10-15, **approved by the user, 2026-10-15**). Found while writing Phase
   17's `CommandLanguage` (`vax-macro32-backend.md`, section 23):
   `CLI$DCL_PARSE` wants `LIB$GET_INPUT`'s address, and poc has no way
   to give it. What poc does today (tried, 2026-10-15):
   - A global Oberon procedure's address is already reachable, as
     `SYSTEM.VAL(SYSTEM.ADDRESS, P)`, on both back ends. Its procedure
     value is its entry address: LLVM's function pointer, the VAX's entry
     mask by `MOVAB`. So `SYSTEM.ADR(P)` is not needed for one, and is not
     proposed.
   - An external procedure's name, `["C"]` or `["VMS"]`, is refused in
     every expression, `VAL`'s argument included: "an external procedure
     cannot be used as a procedure value"
     (`SemanticActions.CheckProcedureValue`). The reason holds for a
     value that Oberon may call: such a value is always called with
     Oberon's convention, hidden arguments included, and an external
     takes C's or VMS's. It does not hold for an address, which Oberon
     cannot call.

   The proposals:
   1. **`SYSTEM.VAL(SYSTEM.ADDRESS, E)` takes an external procedure `E`**,
      declared in the module or imported, and gives the address of its
      linkage name. On the VAX that is `G^name`, VMS's "procedure value,
      by reference". On LLVM it is the C function pointer, which also
      serves C callbacks (`qsort`, `atexit`, `signal`). The target must be
      `SYSTEM.ADDRESS` itself.
   2. **Everything else stays refused, with the present message:**
      - `VAL` of an external to any other type, a procedure type above
        all, since that makes a value Oberon would call with the wrong
        convention;
      - an external assigned, passed as an argument, returned, or compared
        with `=` or `#`.

      Nested, type-bound and predeclared procedures stay refused
      everywhere, `VAL` included, as now.
   3. **Unchecked, as `SYSTEM` is.** An address carries no type, so
      handing VMS or C an external that cannot take what it will be passed
      goes wrong at run time. Nothing else checks it. The text says so.
   4. **Not a new extension.** `VAL` is already `SYSTEM`'s unchecked
      conversion, and external procedures are already poc's own.
      `language-extensions.md`'s "External procedures" and `AGENTS.md`'s
      summary of it each gain a sentence. `-strict` rejects it as it
      rejects an external declaration. poc's own source does not use it.
   5. **Both back ends.**
      - LLVM: the address is the function's `ptrtoint`, and the module
        declares the external even when nothing calls it.
      - VAX: `MOVAB` of the linkage name, the external listed in the
        module as a call lists it, as `ProcedureValue` does for an Oberon
        procedure.

      No runtime change.
   6. **Made on `main`, then merged into `vax`** (the user,
      2026-10-15), where `CommandLanguage` uses it. On `main`:
      - the front end, the LLVM back end, the documents and the gate;
      - `llvm-system-val-external`: C's `qsort` sorts an array of
        `SYSTEM.INT32`, given by `VAL` a C comparison from the fixture's C
        part, declared `["C"]`. A second module importing the first checks
        that `VAL(ADDRESS, E)` gives the same address when `E` is named
        from either module;
      - `semantic-reject-system-val-external`: each refusal of
        proposal 2 with its message, and `-strict`.

      `main` has no VAX back end, so the VAX half (`MOVAB` of an
      external's linkage name, listed as external) and a `vax-` MACRO-32
      fixture showing it are made on `vax` after the merge. There too,
      `vax-vms-calls` gains two calls of `LIB$CALLG`, whose `user_procedure` the generator already declares
      `SYSTEM.ADDRESS`. One passes `VAL(ADDRESS, LIB$PUT_OUTPUT)` with an
      argument list holding a descriptor. The other passes `VAL` of an
      Oberon procedure that VMS can call, and checks the status it
      returns.
   7. **What changes in `vax-macro32-backend.md` section 23** (on `vax`).
      Proposal 3 there becomes:
      `ParsePrompting` passes `SYSTEM.VAL(SYSTEM.ADDRESS,
      LIB$GET_INPUT)` for both routines, as CDU's own example does, from
      Oberon. `CommandLanguage.mar` keeps only the weak reference to the
      table and a routine that returns its address. (As built, there is no
      `CommandLanguage.mar`: the program passes the table's address too,
      section 23.5.)

   **Built on `main` (2026-10-15):** `PredeclaredProcedures.CheckVal`
   marks its operand (`addressedProcedure`), `SemanticActions.
   CheckProcedureValue` lets an external through there alone (and
   `-strict` reports it), and `LLVMCodeGenerator.
   GenerateDesignatorValue` gives `@<linkage name>`. Fixtures
   `llvm-system-val-external` and `semantic-reject-system-val-external`.
   `language-extensions.md` ("External procedures", `-strict`), the
   Reference Guide, the User's Guide ("Calling C") and `AGENTS.md` say
   what it is. `make check` passed on atla, cymoril, artos and alerik
   (360 each, the fixed point and `check-strict` included).

   **Merged into `vax` (509cebd), and the VAX half made there
   (2026-10-15):** `VaxCodeGenerator.Designator` takes an external
   `["VMS"]` procedure's name, which the checker allows only in `VAL`,
   and `ProcedureValue` names it `G^` and `.EXTERNAL`, as a call does.
   Fixtures `vax-external-address` (its `.mar` assembled on the guest and
   reviewed by the user) and `vax-vms-calls` (`LIB$CALLG` of
   `LIB$PUT_OUTPUT` and of an Oberon `Sum`, run on the guest).

## Ongoing implementation enhancements

Changes to how poc builds, links and packages programs and libraries that
using poc on other programs shows are wanted, made as they come,
alongside whichever phase is current. Each item says where the need was
found and what was decided with the user, and is marked `[done]` once it
is committed with its fixtures, `make check` passes on Linux and the
three BSDs, and the User's and Reference Guides and poc(1) say what it
does; a done item stays until the next phase's close-out, which moves it
to that phase's record. Made on `main`, and merged into the `vax` branch
at a convenient point.

Those done while Phase 15 was current, 1-4, are in
`doc/history/phases/phase-15.md`.

## Open design questions

- **The lowest 32-bit x86 CPU** (deferred from Phase 11 to Phase 12 on
  2026-09-26, and here at Phase 12's close-out, 2026-10-02, until the test
  hosts exist).
  poc passes clang no `-march`, so each OS's default CPU applies: pentium4
  for i686 Linux (which may use SSE2), i486 for NetBSD, i586 for OpenBSD,
  i686 for FreeBSD. poc must run on a Pentium II (i686, no SSE), so the
  question is whether to fix `-march=i686` for every 32-bit x86 triple:
  the same code on all four OSes and no SSE2 on Linux, at the cost of 486
  and Pentium machines. x87 reals stay either way. It needs 32-bit x86 test
  hosts first: a 32-bit NetBSD at least, and a 32-bit FreeBSD if FreeBSD
  still ships an i386 build (today only OpenBSD, cymoril, is 32-bit x86).

Decided, with the full reasoning in `doc/developer/design-decisions.md` under the
same names:

- No `ASSERT` (decided 2026-09-25: `doc/research/assert-survey.md`)
- Open array dimension limit
- External procedure declaration syntax
- `-OC`-equivalent elementary-type-size model
- Type guards in designators — two separate gaps
- Predeclared "functions" in constant expressions — really two separate gaps, not one
- Constant arithmetic doesn't re-derive its result's minimal type from the computed value
- Declaration order: voc relaxes CONST/TYPE/VAR *section* order, never reference order
- `SYSTEM.ADDRESS` stays signed (decided 2026-10-08, with the unsigned
  types of Phase 19 candidate 5)
- poc on VAX/VMS has no LLVM back end (decided 2026-10-15, Phase 17
  step 7)

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
- **Phase 14**: `semantic-`, `module-` and `llvm-` fixtures for literals
  and structured constants, accepted and rejected, and the usual gate
  with the Stage 1/2 fixed point.
- **Phase 15**: manual review only (no automated run), explicitly bounded
  in scope as described above.
- **Phase 16**: fixtures run on a real or SIMH-hosted VAX/VMS 5.5-2
  guest; exit gate is the bootstrap fixed point there (V1's `.mar` for
  poc's own source identical to what poc itself produces on VMS).
- **Phase 17**: fixtures on the guest, the AST fixtures repeated, and the
  Phase 16 suite still clean.
- **Phase 18**: the direct-object bootstrap fixed point on the guest, with
  no `MACRO` in the build, and every earlier VAX fixture identical whether
  built through `.mar` or directly.
