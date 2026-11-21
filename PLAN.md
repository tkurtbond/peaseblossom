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
native libraries, and asynchronous system traps.

**Done** (closed 2026-10-16): poc builds VAX libraries, each as an
object library and a shareable image under `-O2` and `-OC`: `POCRTL`,
all of `rtl/llvm`'s interfaces on VMS; `VMSDEF`, 243 modules generated
from `STARLETSD.TLB` by `tools/sdloberon`; and `VMSLIB`, twelve
hand-written modules over `LIB$`, `STR$`, `SOR$`, `CLI$` and the system
services, ASTs among them. A `["VMS"]` declaration passes each argument
as its formal says, an AST routine is an Oberon procedure, and the heap
runs with ASTs disabled. The kits, `POC-<version>.COM` and
`POC-VMS-<version>.COM`, install poc and its libraries on a VMS site.
The VAX fixtures went from 65 to 110, all passing on the guest, the AST
ones 20 times over. The design and every decision are in
`doc/developer/vax-macro32-backend.md`, sections 18-23, and
`doc/developer/vms-sdl-interfaces.md`; the full account (every step,
what was found, the exit review, what is left open) is in
`doc/history/phases/phase-17.md`:

- **1.** Static and dynamic libraries on VMS.
- **2.** Which existing Oberon modules to support on VMS.
- **3.** Implementing them on VMS: `POCRTL`.
- **4.** Which native VAX/VMS libraries to support.
- **5.** Calling native libraries from Oberon: the mechanisms,
  `VMSDEF`'s generator, `VMSLIB`, and fixtures of the supported tier.
- **6.** Asynchronous system traps.
- **7.** Distributing poc on VAX/VMS: the kits; the packages once `vax`
  is merged.
- **8.** Exit gate.

### Phase 18 — Direct VAX/VMS object files (no MACRO-32 in the loop)

**Goal**: `poc` writes VAX/VMS object modules (`.OBJ`) itself, so a
compile is Oberon source to object file and `LINK` is the only VMS tool
left in the build - the assembler (`MACRO`) drops out, and MACRO-32
stays as `-vax-macro32`, the readable form and the oracle.

**Done** (closed 2026-10-21, on the `vax-obj` branch): poc encodes
VAX instructions and writes VMS object modules itself
(`VaxInstructions`, `VaxEncoder`, `VaxObjectWriter`), each module's
image MACRO's byte for byte, for every VAX fixture and poc's own 42
modules. Every object has traceback records, and with `-g` the 5.5-2
debugger works by Oberon source line, variables and their types
included. Objects are poc's default on VMS (`-vax-objects`,
`-vax-macro32`); `-build`, `-compile` and `-library` take either, and
the VAX fixtures and `make test-vax` run both ways. poc rebuilds itself
on the guest from its own objects to a fixed point (V1 = V2 = V3 over
`.OBJ` files, `make vax-stages`), with `MACRO` run only for
`PocRtl.mar`; the kits stay MACRO-32. The VAX fixtures went from 110
to 116. The specification and every decision are in
`doc/developer/vax-object-language.md`; the full account (every step,
the exit review, what is left open) is in
`doc/history/phases/phase-18.md`:

- **1.** The object language, from the 5.5-2 documentation.
- **2.** An instruction-level representation under the code generator.
- **3.** The instruction encoder.
- **4.** The object writer, `VaxObjectWriter.Mod`.
- **5.** Debug and traceback information.
- **6.** Wiring it in: `-vax-objects` and `-vax-macro32`.
- **7.** Bootstrap again over objects, and the exit gate.

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
6. **Arrays whose lengths are run-time values** (the user's question,
   2026-10-27): `VAR buf: ARRAY n OF CHAR` with `n` not a constant, for
   local variables (perhaps unexported module variables), never for
   types, fields or element types. Analysed in
   `doc/research/runtime-length-arrays.md`: storage made on entry as an
   open-array value parameter's copy is now, lengths evaluated once in
   declaration order under A23's rules, typed as an open array, a length
   that is not positive trapping with exit 7, not an assignment target
   at first; the risk is stack exhaustion. **Undecided**; the survey of
   other languages (the Oberons, Algol, Ada, C99, Modula-2 and -3) is
   still to do, as that file's section 8.
7. **Concurrency** (the user's question, 2026-11-13): threads,
   coroutines or nothing. Surveyed in
   `doc/research/concurrency-survey.md` (the Oberons, Modula-2 and -3,
   Ada, Go; pthreads probed on atla, DECthreads on the SIMH VAX). Its
   Proposal's item 1 was **adopted and documented 2026-11-13**: a program
   has one thread, and a signal handler only sets the program's own
   variables, which the main line reads by `SYSTEM.GET` (a plain read in
   a loop was hoisted at `-opt 1` and up, and the loop never ended).
   `language-extensions.md`, "Threads and signal handlers". Documentation
   only: nothing checks either rule. Item 2, an Oakwood `Coroutines`
   module (option B), was **adopted 2026-11-13** and implemented on both
   back ends the same day (`doc/developer/coroutines.md`; "Ongoing
   library enhancements", 4; `language-extensions.md`, "Coroutines").
   Item 3, a cooperative tasks library over it (option C), was
   **adopted 2026-11-14** and implemented on both back ends the same
   day (`doc/developer/tasks.md`; "Ongoing library enhancements", 5;
   `language-extensions.md`, "Tasks"). **Undecided**: a heap re-entry
   trap on LLVM like the VAX's trap 15.

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

## Peaseblossom 0.7.0

What `main` had gained since 0.6.0 was released as **Peaseblossom 0.7.0**
on 2026-10-17: the back end for VAX/VMS 5.5-2 (Phases 15-17, merged from
`vax` at `7ec6468`), with `POCRTL`, `VMSDEF` and `VMSLIB`, the two kits
and the VAX/VMS Guide; `make install-vax` (`7ec6468`) and the
`peaseblossom-vax` packages (`f8acc71`); options after the file name
applied (`1549429`); `SYSTEM.VAL(SYSTEM.ADDRESS, E)` of an external
procedure (`ef4056a`, `f09bcb4` for the VAX); the runtime module
`Directories` (`7e25bbb`); and a note when a missing module is the VAX
runtime's (`153ce20`). The RPM's `%changelog` lists them. It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **Before the version**, every package was built from a `make dist`
  tarball repacked as 0.6.0 and never published, on all seven systems.
  That found the fixes in `a447a9a` (the seed links each module's part in
  C), `67aa737` (`check-vax.sh` in the C locale and without GNU grep's
  `\|`; `Directories` in the OpenBSD and pkgsrc packing lists; pkgsrc's
  `peaseblossom-vax` patches) and `833c792` (`check-install-vax` leaves
  the guide out on a host without pandoc). With the user, the rule was
  set that anything made with pandoc is made on atla by `make dist` and
  put in the tarball (DEVELOPER.md, section 2).
- **The version** was set in `fa7b7b2` by `make set-version`, after
  `tools/check-hosts -t check-install -t check-seed -t check-install-vax`
  passed on atla, cymoril, artos and alerik (477 fixtures at each stage;
  on the BSDs, which have no pandoc, "the guide not checked"). rackhir
  passed `fa7b7b2` (49 minutes), and `make check-vax-kit
  CHECK_VAX_KIT_FLAGS=-full` passed on the guest (33 minutes).
- **The tarball** came from `make distcheck` (SHA-256 `3d674c0d...`,
  11176549 bytes). It is signed, with the signed tag `v0.7.0`, and
  published as a GitHub release with the kits `POC-0-7-0.COM` and
  `POC-VMS-0-7-0.COM`.
- **Each package** was made from the published tarball (`makesum`; the
  `distinfo` files committed after the release, `8c744ce`), then built
  and checked on its system: FreeBSD amd64 (alerik) and arm64 (rackhir),
  OpenBSD i386 (cymoril) and amd64 (jherek), NetBSD amd64 (artos) and
  i386 (yishana); `check.sh` and `check-vax.sh` on the stage,
  check-plist, portcheck and pkglint clean, packing lists unchanged.
  Each was installed as root over the 0.6.0-named test packages, checked
  with `check.sh` and `check-vax.sh` against the installed poc from a
  fresh unpack of the tarball, removed with nothing of its packing list
  left, and installed again. `mock` built and checked the RPMs, and on
  atla 0.7.0 replaces 0.6.0, with `peaseblossom-vax`.
- **`peaseblossom-vax` after `peaseblossom`.** FreeBSD's and pkgsrc's
  `lang/peaseblossom-vax` would not stage until `peaseblossom-0.7.0` was
  installed: FreeBSD's looked for its origin in `/usr/ports`, pkgsrc's
  tried to become root. Each main package was installed first, then the
  vax port built; DEVELOPER.md, section 6, says so (`8c744ce`).
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again, compared with the local copy and checked
  against `SHA256SUMS` and the signatures, the RPMs' with the key in a
  scratch rpm database.

## Peaseblossom 0.8.0

What `main` had gained since 0.7.0 was released as **Peaseblossom 0.8.0**
on 2026-10-21: Phase 18, poc writing VAX/VMS object files itself, with
traceback records and, with `-g`, the VMS debugger's (merged from
`vax-obj` at `f859581`); `-emit-macro32`, `-emit-vax-object` and
`-emit-vax-image` together; and poc's own source type-checking under
`-O2` again (`make check-o2`, `0f91909`). The RPM's `%changelog` lists
them. It was made as `doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `3f9b19d` by `make set-version`, after the
  gate passed on atla, cymoril, artos and alerik (483 fixtures at each
  stage, and the fixed point), with `check-install` and `check-seed` on
  atla. rackhir passed `3f9b19d` (56 minutes), and `make check-vax-kit
  CHECK_VAX_KIT_FLAGS=-full` passed on the guest (117 minutes).
- **The tarball** came from `make distcheck` (SHA-256 `40b5f798...`,
  12724566 bytes). It is signed, with the signed tag `v0.8.0`, and
  published as a GitHub release with the kits `POC-0-8-0.COM` and
  `POC-VMS-0-8-0.COM`.
- **Each package** was made from the published tarball (`makesum`; only
  the `distinfo` files changed), then built and checked on its system:
  FreeBSD amd64 (alerik) and arm64 (rackhir), OpenBSD i386 (cymoril) and
  amd64 (jherek), NetBSD amd64 (artos) and i386 (yishana); `check.sh` and
  `check-vax.sh` on the stage, check-plist, portcheck and pkglint clean
  (rackhir has no `portlint`; alerik linted the same port), packing
  lists unchanged. Each replaced 0.7.0, installed as root, `peaseblossom`
  before the FreeBSD and pkgsrc `peaseblossom-vax` ports were built, and
  was checked with `check.sh` and `check-vax.sh` against the installed
  poc from a fresh unpack of the tarball. `mock` built and checked the
  RPMs, and on atla 0.8.0 replaces 0.7.0, with `peaseblossom-vax`.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again, compared with the local copy and checked
  against `SHA256SUMS` and the signatures, the RPMs' with the key in a
  scratch rpm database.

## Peaseblossom 0.9.0

What `main` had gained since 0.8.0 was released as **Peaseblossom 0.9.0**
on 2026-10-24: poc needing far less memory, most of all on VAX/VMS
(`doc/developer/vms-memory.md`, with the results in
`doc/developer/vms-memory-results.md`). Identifiers are interned in the
symbol table, the syntax tree and the types, and literals' text is sized
to fit (`f8cd832`..`321be40`); the VAX back end encodes each procedure
and checks each module as it writes it (`27f64bd`, `b7596fb`), and its
object writer's sorts skip a list already in order (`a0aa73f`); and the
VAX runtime's collector grows its heap to 1.5 times the live data
(`bf4af40`). poc compiling itself on the guest peaks at 15.5 MB of
virtual memory instead of 103.7 MB, with 52,507 page faults instead of
about 1.8 million and 791 s of CPU instead of about 1,510; on Unix it
peaks at 18.6 MB instead of 162.8 (OpenBSD i386) and 21.0 MB instead of
170.5 (Fedora). It was made as `doc/developer/DEVELOPER.md` section 7
says:

- **The version** was set in `d29a2a5` by `make set-version`, after the
  gate passed on atla, cymoril, artos and alerik (483 fixtures at each
  stage, the fixed point, `check-strict`, `check-install` and
  `check-seed` on each, and `check-opt2` and `check-o2` on atla).
  rackhir passed `d29a2a5`, and `make check-vax-kit
  CHECK_VAX_KIT_FLAGS=-full` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `64ae4e32...`,
  13113764 bytes). It is signed, with the signed tag `v0.9.0`, and
  published as a GitHub release with the kits `POC-0-9-0.COM` and
  `POC-VMS-0-9-0.COM`.
- **Each package** was made from the published tarball (`makesum`; only
  the `distinfo` files changed, packing lists unchanged), then built and
  checked on its system: FreeBSD amd64 (alerik) and arm64 (rackhir),
  OpenBSD i386 (cymoril) and amd64 (jherek), NetBSD amd64 (artos) and
  i386 (yishana). Each replaced 0.8.0, installed as root (both 0.8.0
  packages deleted first: `pkg add` of 0.9.0 over them left the 0.8.0
  kits behind, unowned, on alerik, removed by hand), `peaseblossom`
  before the FreeBSD and pkgsrc `peaseblossom-vax` ports were built, and
  was checked with `check.sh` and `check-vax.sh` against the installed
  poc from a fresh unpack of the tarball. `mock` built and checked the
  RPMs, and on atla 0.9.0 replaces 0.8.0, with `peaseblossom-vax`.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again, compared with the local copy and checked
  against `SHA256SUMS` and the signatures, the RPMs' with the key in a
  scratch rpm database.

## Peaseblossom 0.10.0

What `main` had gained since 0.9.0 was released as **Peaseblossom
0.10.0** on 2026-10-28: poc taking object files and external variables,
for linking with code written in other languages. External variables
(`9f32fbf`; `AGENTS.md`, "External variables"); object files on the
command line, linked by `-build` and put in a library by `-library`, for
LLVM (`4aa4abd`) and for the VAX (`f8a2325`, `088fd3c`), with `OBJCONVERT
-COUNTED` for an object made on VMS (`f9c309d`); each `-link` argument a
line of the VAX link's options file, and a `.opt` among the files
(`9cf0b56`, `088fd3c`); and `-target vax-dec-vms` refusing the LLVM-only
options (`1fff6e8`, `fe168d0`). One fix: a `-link` argument was cut to
255 characters (`9cf0b56`). It was made as `doc/developer/DEVELOPER.md`
section 7 says:

- **The version** was set in `d849a15` by `make set-version`, after the
  gate passed on atla, cymoril, artos and alerik (493 fixtures at each
  stage, the fixed point, `check-strict`, `check-install` and
  `check-seed` on each, and `check-opt2` and `check-o2` on atla). The
  new version first failed three VAX fixtures on the BSDs, whose
  expected records left poc's version out of the LNM record but not that
  record's length, one byte longer with "0.10.0"; they now leave the
  length out too, in the same commit. rackhir passed `d849a15`, and
  `make check-vax-kit CHECK_VAX_KIT_FLAGS=-full` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `9b5834bd...`,
  13432230 bytes). It is signed, with the signed tag `v0.10.0`, and
  published as a GitHub release with the kits `POC-0-10-0.COM` and
  `POC-VMS-0-10-0.COM`.
- **Each package** was made from the published tarball (`makesum`; only
  the `distinfo` files changed, packing lists unchanged), then built and
  checked on its system: FreeBSD amd64 (alerik) and arm64 (rackhir),
  OpenBSD i386 (cymoril) and amd64 (jherek), NetBSD amd64 (artos) and
  i386 (yishana). Each replaced 0.9.0, installed as root (both 0.9.0
  packages deleted first), `peaseblossom` before the FreeBSD and pkgsrc
  `peaseblossom-vax` ports were built, and was checked with `check.sh`
  and `check-vax.sh` against the installed poc from a fresh unpack of
  the tarball. `mock` built and checked the RPMs, and on atla 0.10.0
  replaces 0.9.0, with `peaseblossom-vax`, checked the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again, compared with the local copy and checked
  against `SHA256SUMS` and the signatures, the RPMs' with the key in a
  scratch rpm database.

## Peaseblossom 0.10.1

One fix was released as **Peaseblossom 0.10.1** on 2026-10-28: a
library's manifest records which of its modules allocate (`module <M>
<key> allocates|-`; `2424aea`), so a program whose only `NEW` is in a
library module gets the collector. On VAX/VMS its main now sets the
stack base (before, an object held only on the stack could be freed),
and an LLVM program that never allocates no longer links the collector.
A library an older poc wrote is refused ("rebuild it"). It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `84cde99` by `make set-version`, which also
  removed `BUGS.md`; the gate passed on atla, cymoril, artos and alerik
  (494 fixtures at each stage, the fixed point, `check-strict`,
  `check-install` and `check-seed` on each, and `check-o2` on atla).
  rackhir passed `2424aea`, and `make check-vax-kit
  CHECK_VAX_KIT_FLAGS=-full` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `f4070d8e...`,
  13440342 bytes). It is signed, with the signed tag `v0.10.1`, and
  published as a GitHub release with the kits `POC-0-10-1.COM` and
  `POC-VMS-0-10-1.COM`.
- **Each package** was made from the published tarball, as for 0.10.0
  (only the `distinfo` files changed, packing lists unchanged), on
  alerik, rackhir, cymoril, jherek, artos and yishana, replacing 0.10.0
  and checked against the installed poc. yishana's check first failed
  for a full `/tmp` (a 768 MB tmpfs), filled by the package scripts'
  leftover directories; they were removed and the check passed. `mock`
  built and checked the RPMs, and on atla 0.10.1 replaces 0.10.0, with
  `peaseblossom-vax`, checked the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again and checked against `SHA256SUMS` and the
  signatures, the RPMs' with the key in a scratch rpm database.

## Peaseblossom 0.11.0

What `main` had gained since 0.10.1 was released as **Peaseblossom
0.11.0** on 2026-11-02: the predeclared unsigned types and `VAL`
(`d2a9350`; `AGENTS.md`, "Predeclared unsigned types"), with
`In.HugeCard` and `InStr.HugeCard`, and libraries without a shared
object (`1a925cd`..`c633ba3`; `doc/developer/static-only-libraries.md`).
A function called as a statement is now a compile-time error (`6a8ca4b`):
the sweep of the other poc projects found seven such statements, all in
pofltk's tests, fixed there before the release. Four fixes: no `.sym`
after an error in a module's interface or an import of a file that
declares another module (`6a8ca4b`), such an import says so (`f4d36fc`),
`-compile` no longer calls a file on the command line an imported module
(`984db44`), and the repository checks out on a case-insensitive file
system (`950b2a3`). It was made as `doc/developer/DEVELOPER.md` section 7
says:

- **The version** was set in `0c335b8` by `make set-version`; the gate
  passed on atla, cymoril, artos and alerik (505 fixtures at each stage,
  the fixed point, `check-strict`, `check-install` and `check-seed` on
  each, and `check-o2` on atla). rackhir passed `0c335b8`, and `make
  check-vax-kit CHECK_VAX_KIT_FLAGS=-full` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `3ad9d45b...`,
  13721120 bytes). It is signed, with the signed tag `v0.11.0`, and
  published as a GitHub release with the kits `POC-0-11-0.COM` and
  `POC-VMS-0-11-0.COM`.
- **Each package** was made from the published tarball, as for 0.10.0
  (only the `distinfo` files changed, packing lists unchanged), on
  alerik, rackhir, cymoril, jherek, artos and yishana, replacing 0.10.1
  and checked against the installed poc. The hosts' work trees had been
  cleaned since 0.10.1, so `ports-work/packages/All` and pkgsrc's
  `distfiles` had to be made again first. `mock` built and checked the
  RPMs, and on atla 0.11.0 replaces 0.10.1, with `peaseblossom-vax`,
  checked the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again and checked against `SHA256SUMS` and the
  signatures, the RPMs' with the key in a scratch rpm database.
- **The guest's `DUA1:[POC]`** holds 0.11.0, from the published kits.
  The tree under it held poDMSFIELDS's and poPOISE-DMS's installations
  too, built with 0.10.1, which a new poc refuses: they were deleted
  with it, by the user's decision, to be installed again built with
  0.11.0.

## Peaseblossom 0.11.1

One fix was released as **Peaseblossom 0.11.1** on 2026-11-06: ongoing
bug 18, a string literal in an array index (or a set constructor's
element, or the index of a procedure variable called as a statement)
never emitted on LLVM targets (`834fb98`; "Ongoing bug fixing", 18).
besm2_cg_po's workaround for it was removed with it. It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `185b849` by `make set-version`; the gate
  passed on atla, cymoril, artos and alerik (506 fixtures at each stage,
  the fixed point, `check-strict`, `check-install` and `check-seed` on
  each, and `check-o2` on atla). rackhir passed `185b849`, and `make
  check-vax-kit` passed on the guest (without `-full`: `834fb98` changed
  only the LLVM back end).
- **The tarball** came from `make distcheck` (SHA-256 `07cc9338...`,
  13727442 bytes), after `make stage2` reached the fixed point. It is
  signed, with the signed tag `v0.11.1`, and published as a GitHub
  release with the kits `POC-0-11-1.COM` and `POC-VMS-0-11-1.COM`. The
  user signed over ssh, so `gpg` ran with `--pinentry-mode loopback` in a
  terminal, not with a graphical pinentry.
- **Each package** was made from the published tarball, as for 0.11.0
  (only the `distinfo` files changed, packing lists unchanged), on
  alerik, rackhir, cymoril, jherek, artos and yishana, replacing 0.11.0
  and checked against the installed poc. artos had too little free disk
  for two work trees, so its old ones were cleaned first. rackhir's
  `peaseblossom-vax`, which the release's files do not include, was
  still building when this was written. `mock` built and checked the
  RPMs, and on atla 0.11.1 replaces 0.11.0, with `peaseblossom-vax`.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (20 files) and attached to the release; every
  file was downloaded again and checked against `SHA256SUMS` and the
  signatures, the RPMs' with the key in a scratch rpm database.
- **The guest's `DUA1:[POC]`** holds 0.11.1, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run). The tree held only
  0.11.0 this time.

## Peaseblossom 0.11.2

`BUILDVIAOBJ.COM` was released as **Peaseblossom 0.11.2** on
2026-11-07, the user deciding that it was enough for a release:
the base kit's procedure that rebuilds poc on VMS through the object
back end, checks the fixed point by comparing objects, and installs it
("Ongoing implementation enhancements", 11; `0388813`). The compiler is
the same as 0.11.1's. It was made as `doc/developer/DEVELOPER.md`
section 7 says:

- **The version** was set in `2fe9919` by `make set-version`; the gate
  passed on atla, cymoril, artos and alerik (506 fixtures, the fixed
  point, `check-strict`, `check-install` and `check-seed` on each).
  rackhir passed `2fe9919`. On the guest `check-vax-kit -full` passed
  on `0388813` (about an hour), and `make check-vax-kit` on `2fe9919`.
- **The tarball** came from `make distcheck` (SHA-256 `8f3a4d6d...`,
  13744035 bytes), after `make stage2` reached the fixed point. It is
  signed, with the signed tag `v0.11.2`, and published as a GitHub
  release with the kits `POC-0-11-2.COM` and `POC-VMS-0-11-2.COM`.
  Signing ran in a terminal with `--pinentry-mode loopback`, as for
  0.11.1; gpg-agent still held the key when the RPMs were signed.
- **Each package** was made from the published tarball (only the
  `distinfo` files changed, packing lists unchanged), on alerik,
  rackhir, cymoril, jherek, artos and yishana, replacing 0.11.1 and
  checked against the installed poc. `mock` built and checked the RPMs,
  and on atla 0.11.2 replaces 0.11.1, with `peaseblossom-vax`, checked
  the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` and attached to the release; every file was
  downloaded again and checked against `SHA256SUMS` and the signatures,
  the RPMs' with the key in a scratch rpm database.
- **The guest's `DUA1:[POC]`** holds 0.11.2, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run).

## Peaseblossom 0.12.0

What `main` had gained since 0.11.2 was released as **Peaseblossom
0.12.0** on 2026-11-15: the runtime modules `Coroutines` and `Tasks` on
both back ends (`AGENTS.md`, "Coroutines" and "Tasks";
`doc/developer/coroutines.md`, `doc/developer/tasks.md`; merged as
`fc0f2f0`), the rules for threads and signal handlers (`c67aad2`),
Debian packages from `packaging/debian`, and `make examples` and `make
examples-vax` (`45577e9`), whose VAX/VMS kit of the guide's examples,
`POC-EXAMPLES-<version>.COM`, is now a release file. The compiler itself
is unchanged. It was made as `doc/developer/DEVELOPER.md` section 7
says:

- **The version** was set in `b5a1fa3` by `make set-version`, which
  also made the examples kit one of `make dist`'s and
  `tools/release-files`'s files. The gate passed on cymoril, artos and
  alerik (538 fixtures, the fixed point, `check-strict`,
  `check-install` and `check-seed` on each); on atla
  `vax-tasks-terminal` missed its timing while the guest was loaded,
  and passed run alone, and `check-install` and `check-seed` passed.
  rackhir passed `b5a1fa3`, and `make check-vax-kit` passed on the
  guest.
- **The tarball** came from `make distcheck` (SHA-256 `9f56670a...`,
  14336192 bytes). It is signed, with the signed tag `v0.12.0`, and
  published as a GitHub release with the kits `POC-0-12-0.COM`,
  `POC-VMS-0-12-0.COM` and `POC-EXAMPLES-0-12-0.COM`.
- **Each package** was made from the published tarball (only the
  `distinfo` files changed, packing lists unchanged), on alerik,
  rackhir, cymoril, jherek, artos and yishana, replacing 0.11.2 and
  checked against the installed poc; rackhir's `peaseblossom-vax` is
  alerik's (`FreeBSD:15:*`), not built there. The Debian packages were
  built in a `debian:trixie` container on atla (amd64; its first
  `apt-get` hung on a download for 40 minutes and was run again) and on
  sadric (arm64), where they replace 0.11.2 and were checked the same
  way. `mock` built and checked the RPMs, and on atla 0.12.0 replaces
  0.11.2, with `peaseblossom-vax`, checked the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (24 files) and attached to the release; every
  file was downloaded again and checked against `SHA256SUMS` and the
  signatures, the RPMs' with the key in a scratch rpm database.
- **The guest's `DUA1:[POC]`** holds 0.12.0, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run). The tree held only
  0.11.2.

## Peaseblossom 0.13.0

What `main` had gained since 0.12.0 was released as **Peaseblossom
0.13.0** on 2026-11-15: `Tasks`' `AwaitReadableFor` and
`AwaitWritableFor`, a descriptor wait with a time limit, on both back
ends (`73109d2`), and a second kit of the VAX/VMS Guide's examples,
`POC-EXAMPLES-SOURCE-<version>.COM`, whose `BUILD.COM` builds them with
an installed poc and rebuilds what changed, with Queens and WordSets in
both examples kits (`5fab241`); the source kit is now a release file.
The compiler is unchanged (nothing under `src/` but `Version.Mod`); a
library from an older poc must be rebuilt. It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `553d968` by `make set-version`; the kit
  names in `tools/build-examples` and `tools/build-examples-source`'s
  header comments were changed by hand. The gate passed on atla,
  cymoril, artos and alerik (539 fixtures, the fixed point,
  `check-strict`, `check-install` and `check-seed` on each; atla's
  `check-opt2` 389). rackhir passed `553d968`, and `make
  check-vax-kit` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `2e1d6d41...`,
  14351926 bytes). It is signed, with the signed tag `v0.13.0`, and
  published as a GitHub release with the kits `POC-0-13-0.COM`,
  `POC-VMS-0-13-0.COM`, `POC-EXAMPLES-0-13-0.COM` and
  `POC-EXAMPLES-SOURCE-0-13-0.COM`.
- **Each package** was made from the published tarball (only the
  `distinfo` files changed, packing lists unchanged), on alerik,
  rackhir, cymoril, jherek, artos and yishana, replacing 0.12.0 and
  checked against the installed poc; rackhir's `peaseblossom-vax` is
  alerik's. Over the office's DSL link each host's fetch of the
  tarball from GitHub took about 12 minutes, so rackhir's was copied
  into its distfiles from atla instead; the `debian:trixie` container
  on atla (amd64) took an hour, most of it `apt-get`. sadric built the
  arm64 Debian packages, which replace 0.12.0 there, checked the same
  way. `mock` built and checked the RPMs, and on atla 0.13.0 replaces
  0.12.0, with `peaseblossom-vax`, checked the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (25 files) and attached to the release; every
  asset's SHA-256 as GitHub reports it matches the local file, and
  `SHA256SUMS` and its signature check.
- **The guest's `DUA1:[POC]`** holds 0.13.0, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run). The tree held only
  0.12.0.

## Peaseblossom 0.13.1

Ongoing bug fixing 21 was released as **Peaseblossom 0.13.1** on
2026-11-16: each coroutine's stack is registered with valgrind
(`rtl/llvm/valgrind.h`, valgrind's own header), so memcheck follows a
switch between two of them, for `Coroutines` and `Tasks` alike
(`9ddaf49`). The compiler is unchanged (nothing under `src/` but
`Version.Mod`); only the runtime library changed, so a library from an
older poc must be rebuilt. It was made as `doc/developer/DEVELOPER.md`
section 7 says:

- **The version** was set in `d76ceee` by `make set-version`; the kit
  names in `tools/build-examples` and `tools/build-examples-source`'s
  header comments were changed by hand again. The gate passed on
  cymoril, artos and alerik (540 fixtures, the fixed point,
  `check-strict`, `check-install` and `check-seed` on each); on atla
  only `vax-tasks-terminal` failed, a timing flake under the guest's
  load, which passed run again alone, as did atla's `check-install` and
  `check-seed`. rackhir passed `d76ceee`, and `make check-vax-kit`
  passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `b9d39c3a...`,
  14461933 bytes), with an uncommitted `PLAN.md` stashed while `make
  dist` ran, since it refuses a tree that differs from `HEAD`. It is
  signed, with the signed tag `v0.13.1`, and published as a GitHub
  release with the kits `POC-0-13-1.COM`, `POC-VMS-0-13-1.COM`,
  `POC-EXAMPLES-0-13-1.COM` and `POC-EXAMPLES-SOURCE-0-13-1.COM`.
- **Each package** was made from the published tarball (only the
  `distinfo` files changed, packing lists unchanged), copied to each
  host's distfiles from atla, on alerik, rackhir, cymoril, jherek,
  artos and yishana, replacing 0.13.0 and checked against the installed
  poc; rackhir's `peaseblossom-vax` is alerik's. sadric (arm64, 22
  minutes) and the `debian:trixie` container on atla (amd64) built the
  Debian packages, which replace 0.13.0 on sadric, checked the same
  way. `mock` built and checked the RPMs, and on atla 0.13.1 replaces
  0.13.0, with `peaseblossom-vax`, checked the same way.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (25 files; `DEBIAN_HOSTS="atla sadricstar"`
  away from home) and attached to the release; every asset's SHA-256
  as GitHub reports it matches the local file, and `SHA256SUMS` and its
  signature check.
- **The guest's `DUA1:[POC]`** holds 0.13.1, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run). The tree held only
  0.13.0.

## Peaseblossom 0.14.0

What `main` had gained since 0.13.1 was released as **Peaseblossom
0.14.0** on 2026-11-16: the runtime module `StopRequests`, on both back
ends, so that a program stops cleanly on SIGINT and SIGTERM (CTRL/C on
VMS) with no C of its own (`094363a`), and ongoing bug fixing 19, 20,
22, 23 and 24: `Tasks`' clock on VAX/VMS is the ticks since boot
(`4f2fee1`), a `TaskInput` mailbox read on VMS asks for no more than the
mailbox's message size, `TaskInput` on POSIX reads again after `EINTR`,
`vax-coroutines-asts` ends on its counts (`7c53e77`), and `Coroutines`
loads the time zones on main's stack before the first coroutine
(`094363a`). The compiler is unchanged (nothing under `src/` but
`Version.Mod`); only the runtime libraries changed, so a library from
an older poc must be rebuilt. It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `a410135` by `make set-version`, which
  now also sets the kit names in `tools/build-examples` and
  `tools/build-examples-source`'s header comments, changed by hand at
  0.13.0 and 0.13.1. The gate passed on atla, cymoril, artos and alerik
  (543 fixtures, the fixed point, `check-strict`, `check-install` and
  `check-seed` on each; atla's `check-opt2` 392). rackhir passed
  `a410135`, and `make check-vax-kit` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `9014d87d...`,
  14485487 bytes). It is signed, with the signed tag `v0.14.0`, and
  published as a GitHub release with the kits `POC-0-14-0.COM`,
  `POC-VMS-0-14-0.COM`, `POC-EXAMPLES-0-14-0.COM` and
  `POC-EXAMPLES-SOURCE-0-14-0.COM`.
- **Each package** was made from the published tarball (only the
  `distinfo` files changed, packing lists unchanged), copied to each
  host's distfiles from atla, on alerik, rackhir, cymoril, jherek,
  artos and yishana, replacing 0.13.1 and checked against the installed
  poc; rackhir's `peaseblossom-vax` is alerik's. sadric (arm64, as
  `sadricstar`, 21 minutes) and the `debian:trixie` container on atla
  (amd64) built the Debian packages, which replace 0.13.1 on sadric,
  checked the same way. `mock` built and
  checked the RPMs, and on atla 0.14.0 replaces 0.13.1, with
  `peaseblossom-vax`. The package scripts, lost with the 0.13.1 scratch
  directory, were made again from the 0.12.0 session's.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (25 files; `DEBIAN_HOSTS="atla sadricstar"`)
  and attached to the release; every asset's SHA-256 as GitHub reports
  it matches the local file, and `SHA256SUMS` and its signature check.
- **The guest's `DUA1:[POC]`** holds 0.14.0, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run). The tree held only
  0.13.1.

## Peaseblossom 0.15.0

What `main` had gained since 0.14.0 was released as **Peaseblossom
0.15.0** on 2026-11-20: language enhancement 6, indexing a string
constant, on both back ends (`fcf8491`); library enhancements 8,
`In.Peek` (`2ab53f9`), 3, `OutStr`'s `At` twins (`6f2c778`), and 13,
memcheck no longer reporting the collector's stack scan (`fc3b145`);
`-march=i686` for a 32-bit x86 Linux target (`ba38100`); and ongoing
bug fixing 25-28 and 30-32 (`11884c6`, `feabebc`, `77d80b5`, `4af2776`,
`5e1c880`, `c65de3f`). Both the compiler and the runtime libraries
changed, so a library from an older poc must be rebuilt. It was made as
`doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `39d2137` by `make set-version`. The gate
  passed on cymoril, artos and alerik (557 fixtures, the fixed point,
  `check-strict`, `check-install` and `check-seed` on each). On atla
  `vax-asts-heap` counted 2 collections for its "3 or more" and passed
  run again alone (bug 33); the rest of atla's make check passed, and
  its `check-opt2` (401, twice), `check-install` and `check-seed`
  passed run separately. rackhir passed `39d2137`, and `make
  check-vax-kit CHECK_VAX_KIT_FLAGS=-full` passed on the guest.
- **The tarball** came from `make distcheck` (SHA-256 `7293db3b...`,
  14899771 bytes). It is signed, with the signed tag `v0.15.0`, and
  published as a GitHub release with the kits `POC-0-15-0.COM`,
  `POC-VMS-0-15-0.COM`, `POC-EXAMPLES-0-15-0.COM` and
  `POC-EXAMPLES-SOURCE-0-15-0.COM`.
- **Each package** was made from the published tarball (only the
  `distinfo` files changed, packing lists unchanged), copied to each
  host's distfiles from atla, on alerik, rackhir (after its check),
  cymoril, jherek, artos and yishana, replacing 0.14.0 and checked
  against the installed poc. sadric (arm64, as `sadricstar`, 23 minutes)
  and the `debian:trixie` container on atla (amd64) built the Debian
  packages, which replace 0.14.0 on sadric, checked the same way. The
  installs on the VMs and sadric went by `ssh root@<host>`, not root
  panes. `mock` built and checked the RPMs, and on atla 0.15.0 replaces
  0.14.0, with `peaseblossom-vax`, checked the same way. The package
  scripts, lost with the 0.14.0 scratch directory, were made again from
  the 0.12.0 session's.
- **The RPMs and `SHA256SUMS`** were signed, gathered by
  `tools/release-files` (25 files; `DEBIAN_HOSTS="atla sadricstar"`;
  one run stopped at a moment sadricstar did not answer, and gpg timed
  out waiting for the passphrase, so the user signed `SHA256SUMS`) and
  attached to the release; every asset's SHA-256 as GitHub reports it
  matches the local file, and `SHA256SUMS` and its signature check.
- **The guest's `DUA1:[POC]`** holds 0.15.0, from the published kits,
  checked as `POC2` (`HELLO.MOD` built and run). The tree held only
  0.14.0.

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

Those fixed while Phase 18 was current, 8-10, are in
`doc/history/phases/phase-18.md`.

11. **[fixed] On the VAX, a program whose main module calls no `NEW`
    got no collector setup, even when a library module it uses
    allocates.** Found 2026-10-28 by poDateTime's VAX port, with 0.10.0:
    `TimeZones.FromFile`, from the prebuilt `podatetime` library, lost
    the zone it was building to a collection (an ACCVIO under `-OC`).
    The driver set `VaxCodeGenerator.withCollector`, which makes
    `<MAIN>_MAIN` call `GarbageCollectedHeap`'s initializer and
    `SetStackBase(FP)`, only when a module compiled in that run called
    `NEW`. A library module's `.sym` cannot say whether it does, so
    `stackBase` stayed 0 and no collection marked from the stack. Now a
    library's manifest says which of its modules allocate (`module
    <Module> <key> allocates`, else `-`: their generated code calls
    `GarbageCollectedHeap.Allocate`, by `NEW` or `SYSTEM.NEW`), and a
    library without it is refused ("rebuild it"). Both back ends use it
    (`Poc.NeedsCollector`), so LLVM's `AddRuntimeModules` no longer adds
    the collector to every program with a module from a library while a
    library has `GarbageCollectedHeap`: a program using only poc-rtl's
    `Out` now links without it. Fixture `vax-collector-library`:
    HOLDLIB's manifest, `MAIN_MAIN` from `-emit-macro32` and `-build`
    against a library that allocates and none against one that does not,
    and on the guest, objects held only by a local survive the
    collections the library forces (without the fix the run fails with
    `%X10000022`); the expected manifests of `llvm-cxx-part` (its
    `greeter` no longer needs `poc-rtl`), `llvm-libraries`,
    `llvm-using-modules`, `poc-object-files`, `vax-library`,
    `vax-library-object-files` and `vax-options-files`.

12. **[fixed] An import of a file that declares another module got a
    false error.** Found 2026-11-01, asking how module names and file
    names relate. A module is named by the identifier after `MODULE`,
    and an import finds `<Name>.Mod` or `<Name>.mod` by the name
    imported, so `IMPORT Named` of a `Named.Mod` holding `MODULE Other`
    can never work. poc said "unknown imported module: Named" and then
    "no Named.Mod, Named.mod or Named.sym in the current directory", of
    a directory that has that file. Now `RegenerateInterfaces` compares
    the two: "Named.Mod:1:1: error: this file declares module Other, so
    it cannot be imported as Named". A name differing only in case
    differs, which also gives this message where a case-insensitive
    file system finds the file for the wrong spelling. A file named on
    the command line, or a library's member, may still have any name:
    its outputs are named after its module. Fixture
    `poc-import-wrong-module`.

13. **[fixed] That failure left a `.sym` behind.** Found with 12: the
    file's interface was written before the import was found to fail,
    under the name the file declares, so the failed build above left an
    `Other.sym`, which no command had asked for and a later `IMPORT
    Other` would have read. The check of 12 comes first, so nothing
    is written. `poc-import-wrong-module` lists the `.sym` files after
    each failure.

14. **[fixed] Two tracked files differed only in case, so the repository
    would not check out on a case-insensitive file system.** Reported
    by a user on macOS, 2026-11-01:
    `test/conformance/vax-build/VAXCASE.mod` and `VaxCase.mod`, which
    `vax-build` compiles to show that two modules with the same VMS
    init symbol are refused. git showed one as modified from the start.
    The fixture now writes them, with `VaxBuildCase.mod`, into a
    directory it makes, and compares that part with `expected-case`.
    Where the second file would overwrite the first it says `SKIPPED:`
    and goes on, its `result` the same on every host.

15. **A function procedure can be called as a statement** [fixed]. Found
    2026-11-01 writing `semantic-reject-predeclared-val`: `VAL(CARDINAL,
    n)` alone as a statement was accepted, and so, in a probe, are
    `F()`, `F`, a procedure value's `pv()`, a type-bound `r.M()`,
    `ABS(n)`, `MAX(INTEGER)`, `ODD(n)` and `SYSTEM.VAL(LONGINT, n)`, in
    0.10.1 too. `poc -build` gives a program that throws the result away.
    The report keeps the two apart (section 10: a function procedure is
    activated by a function designator as a constituent of an expression,
    a proper one by a procedure call), and voc refuses it, err 55,
    "procedure call of a function". The check belongs in the checking
    of a call statement, for user and predeclared procedures both; it
    should say which procedure, and it needs a `semantic-reject-` fixture.
    voc's refusal keeps it out of `src/`, which Stage 0 compiles, but not
    out of what only poc compiles, so `rtl/llvm`, `rtl/vax` and the
    fixtures may have calls to correct. Fixed:
    `SemanticActions.CheckCallStatement` says "a function procedure cannot
    be called as a statement" and the name, for ordinary, external,
    type-bound and predeclared procedures and procedure values. `rtl/llvm`,
    `rtl/vax` and the VMS libraries had no such call, and one fixture did
    (`llvm-nested-basic`). Fixture `semantic-reject-function-statement`.

16. **An error found while writing a `.sym` leaves the file behind, and
    the compile carries on** [fixed]. Found 2026-11-01 with the refusals of the
    predeclared unsigned types (`exportedval.mod` in
    `semantic-reject-predeclared-val`): `ModuleInterface.Write` reports
    the error but still registers the file and returns TRUE, so `poc
    -compile` exits 1 with the `.sym`, `.ll` and `.o` written, and the
    `.sym` holds a line the error said could not be written. A later
    `IMPORT` would read it, as in 13. The older errors raised there
    (`ModuleInterface.PrintConstValue`) take the same path. `Write` should
    leave nothing behind and its callers stop, as they do for an error
    before it; the fixture should then list the files after each refusal.
    Fixed: after its dry passes `Write` makes one more with errors
    reported, and makes the file only if that found none; its three
    callers stop and say how many errors there were, for a module
    regenerated for an importer too. `poc -check` writes no interface, so
    it still passes a module whose interface would be refused, and
    `semantic-reject-predeclared-val` shows `-emit-interface`, `-build` and
    an importer's `-compile` leaving only the sources.

17. **`-compile` calls the file it was given an imported module** [fixed]. Found
    2026-11-01 with 16: an error in the command-line file itself, with
    nothing imported, prints `1 error(s) in imported module bad` and then
    `1 error(s)` under `poc -compile bad.mod`, where `-build` and `-check`
    print only `1 error(s)`. The file is checked through the code that
    regenerates an importer's modules (`RegenerateInterfaces` in
    `src/driver/Poc.Mod`), whose message assumes an importer. Only the
    message is wrong: the exit status is 1 and nothing is written.
    Fixed: `ReportImportedErrors` prints that line only for a module that is
    not named on the command line, so `-compile`, `-library` and the VAX's
    two say only the total for such a file, whoever imports it.
    `module-import-error-path` and `vax-module-name-length` show them.

18. **A string literal in an array index is never emitted** [fixed]. Found
    2026-11-06 by besm2_cg_po's tests (`~/Repos/RPG/Tools/besm2_cg_po`,
    `test/TestModel.Mod` and `test/TestWindow.Mod`), with 0.11.0
    (0c335b8). A string passed to a procedure called inside an index,
    `a[F("ab")] := 1` or `x := a[F("ab")]`, is referenced in the `.ll`
    but its constant is never defined, so clang refuses the module:
    "use of undefined value '@.str.IdxStr.L7.C7'", and `poc: build
    failed`. Under `-O2` and `-OC` both. The smallest program:

    ```
    MODULE IdxStr;
    VAR a: ARRAY 4 OF INTEGER;
    PROCEDURE F(s: ARRAY OF CHAR): INTEGER;
    BEGIN RETURN SHORT(LEN(s)) MOD 4
    END F;
    BEGIN
      a[F("ab")] := 1
    END IdxStr.
    ```

    (`poc -OC -o idx IdxStr.Mod`). The string literals are probably
    collected by a walk that does not go into an index's expression.
    Until it is fixed, besm2_cg_po computes the index into a variable
    first (`i := F("ab"); a[i] := 1`). It needs an `llvm-` fixture, and
    a look at the VAX back end for the same gap.
    Fixed (2026-11-06): the walk was
    `LLVMCodeGenerator.CollectStringConstants`, which went into a call's
    arguments but not a designator's selectors, an assignment's target,
    a call statement's procedure designator or a set constructor's
    elements; it now goes into all four (`CollectDesignatorStrings`,
    `CollectSetElements`), and so does the walk that allocates the stack
    slots of structured literals, which is the same one. The VAX back end
    never had the gap: the same program, run by `tools/vax-suite` from
    MACRO-32 and from objects under `-O2` and `-OC`, printed what it
    should while the host build still failed. Fixture
    `llvm-string-in-index` (`-O2` and `-OC`; the index on either side of
    `:=`, two-dimensional, of a field, of a local, in a set and in a call
    through a procedure variable), also in `test/vax-suite.list`.

19. **`vax-coroutines-asts` depends on how fast the guest runs** [fixed]. Found
    2026-11-14, in Tasks Phase 9's gate: with atla busy with `make check`
    and three hosts' copies, the objects way printed "collections during
    the run: 2" where the fixture expects "3 or more"; the macro32 way,
    and the rerun in the same `make check`, passed. The program stops
    after 200 batches of its 10 ms timer AST, about 2 s of the guest's
    clock, so how much the coroutines allocate in that time, and so how
    many collections run, follows from how fast SIMH runs. A likely fix:
    the main loop goes on until it has both its batches and 3 collections,
    so the count is a condition of the run's end, not of its speed.
    Seen again 2026-11-14 in Phase 10's gate, the objects way on atla,
    with a rerun that passed, and 2026-11-16 in bug 22's full run.
    Fixed 2026-11-16: the main loop goes on past its 200 batches until
    there have been 3 collections and 10 lists of the coroutines, but
    never past 2000 batches (about 20 s of the guest's clock), so that a
    run that can't get them still ends and prints its counts rather than
    hanging. The expected output is unchanged.

20. **TaskInput takes a failed mailbox read for the end of the input** [fixed].
    Found 2026-11-14, in Tasks Phase 12's `vax-tasks-examples`: a
    feeder's mailbox made with a maximum message of 64 bytes (`$CREMBX`)
    gave the spawned Clock "end of input" at its first read, before
    anything was written. TaskInput reads a mailbox by `$QIO` into its
    buffer of 512 bytes, the read fails, and `ReadRecord` sets `atEnd` on
    any failure but `SS$_BUFFEROVF`; the subprocess's DCL then read the
    commands meant for Clock, and its `STOP` ended the subprocess. With a
    maximum of 1024 (the fixture's fix) it works. A likely fix: read at
    most the mailbox's maximum message size (`DVI$_DEVBUFSIZ`, asked for
    with the device class), and make a failure other than the end of
    file an error, not the end. The status the read returns is still to
    be seen.
    Seen 2026-11-16, by a probe on the guest: a `$QIOW` read asking for
    more than a mailbox's largest message (512 or 65 of a 64-byte
    mailbox) fails at the call itself with SS$_MBTOOSML (412), IOSB
    untouched, and leaves the message queued, so a read of 64 then gets
    it; `$GETDVIW`'s DVI$_DEVBUFSIZ gives the 64, by name or by channel.
    Fixed the same day: `Choose` asks a mailbox for DVI$_DEVBUFSIZ, and
    `ReadRecord` reads at most that, or 512 if it is larger. Any other
    failure stays the end of the input, not an error: the interface has
    only `Done` to say so, and `rtl/llvm/TaskInput.Mod` takes an error
    for the end too. `vax-tasks-examples`' ClockFeeder makes its mailbox
    with 64-byte messages again, which is the regression test.

21. **[fixed] valgrind's memcheck can't follow a program's coroutines**. Found
    2026-11-15 by posockets (`~/Repos/Oberon/posockets`), Phase 4, with
    0.12.0 and valgrind 3.27.1 on Fedora 44 (x86-64): its `TestTasks`,
    twenty connections served by tasks in one program, gave memcheck's
    limit of 10,000,000 errors, and a program of two tasks that only
    `Tasks.Yield`, with nothing of posockets, gave 23 from 15 contexts.
    memcheck warns "client switching stacks?" at the switches, then
    reports uninitialised values and invalid reads on the coroutine
    stacks. `--max-stackframe` doesn't help. `CoroutinesNewStack`
    (`rtl/llvm/Coroutines.c`) `mmap`s each stack and doesn't tell
    valgrind it is one. A likely fix, not yet tried:
    `VALGRIND_STACK_REGISTER(low, high)` there and
    `VALGRIND_STACK_DEREGISTER` in `CoroutinesFreeStack`, from
    `<valgrind/valgrind.h>` (a few instructions when not under
    valgrind), behind `#ifdef` where the header may be missing. Until
    then posockets runs its task tests under `valgrind --tool=none
    --track-fds=yes`, for open descriptors only, so memcheck checks
    nothing a task runs. Analysed 2026-11-15
    (`doc/developer/coroutines-under-valgrind.md`): a switch between two
    neighbouring coroutine stacks is taken for a push or a pop;
    registering the stacks, tried, leaves 0 errors. The plan copies
    `valgrind.h` into `rtl/llvm` and keeps each stack's id in its
    descriptor. Fixed 2026-11-15 so, with the fixture
    `llvm-coroutines-valgrind` (0 errors from the two-task program,
    `Primes 50` and `Queens`; skipped where there is no valgrind).

22. **Tasks' deadlines on VAX/VMS move when the clock is set** [fixed]. Found
    2026-11-16, planning "Ongoing library enhancements" 7 with the user.
    `rtl/vax/TaskWaiting.Now` reads `$GETTIM`, the system clock, which
    on VMS 5.5-2 is local time, set with `$SETIME` at the changes of
    daylight saving time (on the user's production VAX, every night
    from a NIST time server). `Tasks` measures its deadlines and timers
    with `Now` (`rtl/vax/Tasks.Mod`), so when the clock is set back an
    hour a deadline comes an hour late, and set forward, an hour early;
    `Wait`'s own `$SETIMR` is a delta time and is not affected. The fix
    is poDateTime's (its Q8, `src/vax/TimePlatform.Mod`): read
    `EXE$GL_ABSTIM_TICS`, the 10 ms ticks since boot, through
    `SYS.STB`, counting its wraps every 497 days. How POCRTL, or a
    program using `Tasks`, gets linked with `SYS.STB` is part of the
    fix. A fixture can't set the guest's clock unprivileged, so it
    checks only that `Now` never decreases and follows elapsed time.
    Fixed 2026-11-16: `Now` reads the cell, declared as an external
    variable, and counts its wraps. `SYS.STB` comes by
    `-link 'SYS$SYSTEM:SYS.STB/SELECTIVE_SEARCH'`, with no change to the
    driver: given when `POCRTL` is built (the GNUmakefile, the kits,
    every fixture that builds its own), it is recorded in `POCRTL`'s
    manifest, so it reaches `POCRTL`'s own shareable link and every
    program and library linked against `POCRTL`; a program that takes
    `Tasks` from `rtl/vax`'s source names it beside
    `COROUTINESWITCH.OBJ` (the *VAX/VMS Guide*, "Tasks"). Only an
    image that refers to the cell takes a version dependency (checked
    by `ANALYZE/IMAGE`: a program linked with the line but not with
    `TaskWaiting` has an empty system version array; one using `Tasks`
    has `SYS$K_STABLE` 1.80 alone), so `POCRTL.EXE` and a program that
    links `TaskWaiting` must be linked again only if that category's
    major version changes. Without the line, the link fails on the undefined
    `EXE$GL_ABSTIM_TICS` (checked). `vax-tasks-time` checks that `Now`
    never goes back over 10000 reads, and moves within 20 ms of the
    system time over a 500 ms sleep.

23. **TaskInput on POSIX takes a read that EINTR interrupts for the end
    of the input** [fixed]. Found 2026-11-16, while weighing an error
    report for bug 20: `doc/developer/tasks.md` said `Platform`'s C
    retries a read that EINTR interrupts, but `PlatformRead` retries
    nothing (only `PlatformWrite` does), and `Fill` set `atEnd` on any
    failure, so a signal caught by a handler installed without
    `SA_RESTART`, arriving while the read blocked, ended the program's
    input for good. Unlikely, since the read follows a poll that found
    the descriptor readable, but possible if another process takes the
    data between them. Fixed the same day: `Fill` waits and reads again
    after EINTR. Checked with strace, which made the first read of
    standard input fail with EINTR: before, `input lines` printed only
    `end`; after, every line. `llvm-tasks-input` now makes that check
    where strace can inject faults, and skips it, saying so, elsewhere.
    VMS has no EINTR, so `rtl/vax/TaskInput.Mod` is unchanged.

24. **`Platform.GetClock`'s first call overruns a small task stack on
    NetBSD amd64 and OpenBSD i386** [fixed]. Found 2026-11-16, checking
    first for "Ongoing library enhancements" 7. `PlatformGetClock` calls
    `localtime`, and libc loads the local time zone on the first
    `localtime` or `gmtime` of the process (on NetBSD the UTC zone too,
    on `gmtime`), reading the zone file into buffers on the stack. Probes
    of one `GetClock` in a task of each size found that NetBSD amd64 and
    OpenBSD i386 need more than 32 KiB, and 48 KiB is enough; a 16 KiB
    task, the least, overran its guard page (SIGSEGV). It was the same as
    pogemini's `gmtime_r`. A `GetClock` on the main stack first avoided
    it. Fixed the same day: `CoroutinesNewStack` (`rtl/llvm/Coroutines.c`)
    calls `localtime` and `gmtime` once, before the first coroutine
    stack is made, so still on main's stack; later calls reuse what was
    loaded, unless `TZ` changes. The fixture `llvm-tasks-clock` calls
    `GetClock` first in a 16 KiB task, with the local zone and with
    `TZ=Europe/London`.

25. **`In.Int`, `In.LongInt`, `InStr.Int` and `InStr.LongInt` truncate a
    number too large for their variable and still set `Done`** [fixed]. Found
    2026-11-18, surveying the bindings' integer conversions
    (`doc/developer/sized-integers-and-cardinals-reviewd.md`). Each reads
    a `HUGEINT` and stores `SYSTEM.VAL(INTEGER, h)` or
    `SYSTEM.VAL(LONGINT, h)` (`rtl/llvm/In.Mod:118, 125`,
    `rtl/llvm/InStr.Mod:81, 90`, `rtl/vax/In.Mod:125, 132`). Under `-O2`,
    `In.Int(i)` reading `70000` gives `i = 4464` with `In.Done` TRUE
    (reproduced on atla). A value that does not fit should leave
    `Done` FALSE, as a malformed number does. Fixed 2026-11-18, in both
    back ends' `In` and `InStr`: a number outside the variable's range is
    Done FALSE, value 0, as one that is not a number; `In` has read past
    it, `InStr` leaves `pos` where it was. This was a documented choice,
    voc's (`In.Mod`'s list of differences said Int and LongInt keep the
    low bits); the list now says poc's differ. `llvm-in-extra` checks
    `In` under `-O2`, `llvm-instr` `InStr` under both models, and their
    VAX twins the same on the guest.

26. **`Files` on 32-bit targets truncates a seek position of 2^32 or
    more, so it seeks to the wrong place** [fixed]. Found 2026-11-18, in the same
    survey; from the code, not yet reproduced (it needs an i386 host and
    a file over 4 GiB). `Files.PositionStream`
    (`rtl/llvm/Files.Mod:262`) passes `SYSTEM.VAL(SYSTEM.ADDRESS,
    position)` to `fseek`, whose offset is a C `long`: under `-OC` on
    i386 a 64-bit `LONGINT` position is cut to 32 bits, so position
    2^32 + k seeks to k, and one from 2^31 is a negative offset (a
    "seek failed" trap). A file's length is capped at `MAX(LONGINT)`,
    not `MAX(SYSTEM.ADDRESS)`. Either `fseeko`/`ftello` with a 64-bit
    `off_t` through `Files.c`, or a check that fails a position above
    what `long` holds. Fixed 2026-11-18 with the check: `PositionStream`
    fails ("seek failed") a position above the largest word, so a file
    is limited to what both a `LONGINT` and a `long` hold, as `Files`'
    header now says (`OpenOld` already refused a longer file, whose
    `ftell` fails). Large files on 32-bit systems would need
    `fseeko`/`ftello` and, on Linux, `_FILE_OFFSET_BITS=64` for `fopen`
    and `fwrite` too; not done. Not reproduced, for the reason above.

27. **`MAX(SYSTEM.ADDRESS)` and `MIN(SYSTEM.ADDRESS)` are refused** ("MAX/MIN
    requires a basic type or SET") [fixed]. Found 2026-11-18, fixing bug 26.
    `AGENTS.md` makes `ADDRESS` an integer type, and `MAX`/`MIN` take
    `SYSTEM.CARDn`, `SYSTEM.INTn` and even `SYSTEM.CARD`, as wide as
    `ADDRESS` (checked), but not `ADDRESS` itself.
    `GarbageCollectedHeap` and now `Files` compute it in their module
    bodies by doubling until the value wraps.
    - Fixed (2026-11-18): `ConstantEvaluator.MaxMinBound` gives `ADDRESS`
      the bounds of a signed integer of the target's word size (`2^31 - 1`
      and `-2^31` on 32-bit LLVM targets and the VAX, `2^63 - 1` and
      `-2^63` on 64-bit), typed `ADDRESS`, folded and exported as any other
      `MAX`/`MIN`. The fixture `llvm-max-min-address` checks them on the
      host against the doubled bounds, through a `.sym`, and as the 32-bit
      and 64-bit targets write them; `vax-max-min-address` as the VAX
      writes them (apart, since `make check-opt2` gives poc `-opt 2`,
      which the VAX target refuses).
    - Still to do (the user, 2026-11-18): `GarbageCollectedHeap`
      (`rtl/llvm`, `rtl/vax`) and `rtl/llvm/Files.Mod` keep the doubling
      for now, so that a released poc without this fix (a `BOOTSTRAP_POC`,
      or an installed poc on the VAX guest) still compiles them; their
      comments say so. Once a release has this fix, replace the doubling
      with `MIN(SYSTEM.ADDRESS)` and `MAX(SYSTEM.ADDRESS)`.

28. **The collector frees an object of a record with no fields while it
    is still reachable, on 64-bit targets** [fixed]. Found 2026-11-18 by
    pogeminilib (`~/Repos/Oberon/pogeminilib`, its PLAN.md, Phase 4),
    with 0.14.0 under `-OC` on Fedora 44 (x86-64): an abstract
    `Waiter`, an extension of an empty record held in a global, was
    swept, and a later method call on it crashed. `Allocate`
    (`rtl/llvm/GarbageCollectedHeap.Mod`) takes a `dataSize` of 0, and
    `BlockBytesFor(0)` is the two header words alone, `2 * word`: 16 on
    a 64-bit target, exactly one granule. The data address, block + 2
    words, is then the next block's start, so `MarkCandidate`'s
    `FindBlock` finds that block for it and marks it, and the empty
    object's own block stays unmarked and is swept. On a 32-bit target
    the words are 8 bytes, rounded up to the 16-byte granule, so the
    address stays inside its block (from the code; not run on i386).
    Shown by
    this program: after the collections the empty record's header
    reads free (64), the one-field record's in use (34), and `e.Hi()`
    segfaults:

    ```
    MODULE RD;
    IMPORT SYSTEM, Out;
    TYPE E = POINTER TO ED; ED = RECORD END;
      F = POINTER TO FD; FD = RECORD x: LONGINT END;
    VAR e: E; f: F; i: LONGINT; c: POINTER TO ARRAY OF CHAR; h: SYSTEM.ADDRESS;
    PROCEDURE (e: E) Hi(): INTEGER; BEGIN RETURN 1 END Hi;
    BEGIN
      NEW(e); NEW(f);
      FOR i := 1 TO 200 DO NEW(c, 300000) END; c := NIL;
      SYSTEM.GET(SYSTEM.VAL(SYSTEM.ADDRESS, e) - 16, h); Out.Int(h, 0); Out.Ln;
      SYSTEM.GET(SYSTEM.VAL(SYSTEM.ADDRESS, f) - 16, h); Out.Int(h, 0); Out.Ln;
      Out.Int(e.Hi(), 0); Out.Ln
    END RD.
    ```

    pogeminilib works round it with a field in the empty record.
    - Fixed (2026-11-18): `Allocate` gives a `dataSize` of 0 one byte,
      so every object's data address lies inside its own block (16 more
      bytes per empty object on 64-bit, nothing on 32-bit), and
      `TraceBlock` no longer looks up a NIL pointer field. Fixture
      `llvm-gc-empty-record`. `doc/developer/collector-empty-records.md`
      has the analysis, the other fixes tried, and their costs in time
      and memory: poc itself allocates no empty objects, and marking
      runs 2.6% fewer instructions.

29. **`tools/bench/gc-compare.sh`'s poc-ir workload stops at once**
    [fixed]. Found
    2026-11-18 measuring bug 28's fix: its import path is
    `src/front`, `src/back/llvm` and `rtl/llvm` only, so poc cannot find
    the VAX back end's modules (`src/back/vax`, `src/back/vax/host`) or
    `src/driver`, `src/driver/llvm` and `build/gen`, emits nothing, and
    the script, under `set -e`, ends after printing gcbench's rows with
    no message. It should use the same import path as
    `tools/bootstrap/stage1`, with `-clear-library-path
    -clear-import-path`.
    - Fixed (2026-11-18): the workload uses `tools/bootstrap/stage1`'s
      import path (the directories the old tree has), and
      `-clear-library-path -clear-import-path` where the tree's poc has
      them, for gcbench too. A failure is reported with the end of
      poc's output. The IR is compared without the lines that name
      interface keys (`-key.`), which hash `.sym` files whose layout
      differs between versions of poc while the code is the same.

30. **Three stray tokens before `MODULE` crash poc with a NIL pointer
    dereference** [fixed]. Found 2026-11-19, with 0.14.0 (a410135) on
    x86_64, researching UTF-8 support: a source file that starts with a
    UTF-8 byte order mark (`EF BB BF`) crashes poc. The bytes need not
    be invalid: any three tokens, or invalid characters, before `MODULE`
    do it (`###`, `)))`, `# # #`, the three BOM bytes, and the same
    followed by a newline). One or two (`##`, `EF`, `EF BB`) give
    ordinary errors and exit status 1. The smallest program:

    ```
    ###MODULE B; END B.
    ```

    `poc -check` (or `-compile`) prints the parse errors, then dies,
    with exit status 4:

    ```
    C.Mod:1:1: error: expected 'MODULE'
    C.Mod:1:2: error: expected an identifier
    C.Mod:1:3: error: expected ';'
    C.Mod:1:4: error: expected 'END'
    C.Mod:1:12: error: expected '.'
    NIL pointer dereference
    ```

    Whether poc should skip a leading BOM is a separate question, taken
    up in the UTF-8 research
    (`~/Repos/Oberon/pounicode/docs/developer/adding-utf8-reading-to-poc.md`).
    - Cause: the stray tokens are not the point. The parser takes the
      three as `MODULE`, the module's name and `;`; the name, not an
      identifier, is NIL after `ExpectIdent` reports it, and the `END
      B` that follows does name one. `Parser.ReportEndName`, comparing
      the two, gave up only when the END's name was NIL and dereferenced
      the block's. `MODULE 1; END B.` and `MODULE B; PROCEDURE 1; END
      P; END B.` crash the same way, with no stray tokens. One or two
      stray tokens shift the parse so that the END has no name.
    - Fixed (2026-11-19): `ReportEndName` reports nothing when either
      name is missing; `ExpectIdent` has reported the error. Fixture
      `parser-reject-unnamed-end` has the module, the procedure, `###`
      and the byte order mark.

31. **The VAX back end refuses a structured constant indexed with a
    variable** [fixed]. Found 2026-11-19, with 0.14.0 (a410135), by
    another session: `squares[i]`, with `CONST squares = Squares{0, 1,
    4, 9}` and `i` a variable, gives "the VAX backend cannot lower this
    yet: this designator as a value"; so do `points[i].x`,
    `named.values[i]` and `grid[i]` passed to an open array. A
    constant index works, since the front end folds it, and the LLVM
    back end takes them all: it addresses the constant's private global
    as a variable (`LLVMCodeGenerator`, "Structured constants"). The VAX
    back end has the storage too, `L_CONST_<n>` in `POC_CONST`
    (`StructuredOperand`, 2026-10-11), but used it only to copy the
    whole constant or pass its address: `Designator` took only a
    variable's name, and `Locate`, which applies the selectors, started
    from `Variable(obj)`.
    - Fixed (2026-11-19): `Locate` starts from `StructuredOperand` for a
      record or array constant, and `Designator` passes such a constant
      with selectors to it, so its elements and fields are selected as a
      variable's are, index checks included. Fixture
      `vax-structured-constant-index` (its `expected-vax.mar` reviewed
      by the user, 2026-11-19), its program in `test/vax-suite.list`
      under `-O2` and `-OC`; `vax-macro32-backend.md` says so.

32. **The LLVM back end does not fold a selector on a structured constant
    in a statement** [fixed].
    Found 2026-11-19, with 0.14.0 (a410135) on x86_64, testing
    re-exported structured constants ("Ongoing implementation
    enhancements", 14). `squares[2]`, with `CONST squares = Squares{0,
    1, 4, 9}`, and `o.y`, with `CONST o = M3.Point{x := 5, y := 6}`, in
    a statement are loads from the module's private copy
    (`@L.-const.<n>`), with a run-time index check on constants
    (`icmp sge i8 1, 0`, `icmp slt i8 1, 2`), not the constants 4 and 6.
    The same with an imported constant (`M3.origin.x`,
    `M3.identity[1,1]`) and a re-exported one (`M2.origin.x`, M2
    declaring `origin* = M3.origin`). In a constant declaration it is
    folded: `CONST ox = M3.origin.x` is 0.
    - The language says they are constants:
      `doc/developer/record-and-array-literals.md` makes a selector of a
      structured constant, with constant indexes, a constant expression,
      folded like any other, and says the importer folds `M.Origin.x`.
      The front end does: `ConstantEvaluator.IsConstantExpr` is TRUE of
      `squares[2]` and `o.y`, and `Evaluate` gives 4 and 6.
    - The VAX back end folds them already (checked 2026-11-19):
      `VaxCodeGenerator`'s expression code asks `IsConstantExpr` of every
      expression first, so `i := squares[2]` is `MOVW #4, ...` and `o.y`
      is pushed as `#6`, with no `L_CONST_<n>`.
    - The LLVM back end does not: `GenerateExpr`
      (`src/back/llvm/LLVMCodeGenerator.Mod`) folds only unary, binary
      and set expressions and some calls, through
      `GenerateFoldedInteger`, and only to an integer or a set; a
      designator goes to `GenerateDesignatorValue`, which addresses the
      constant's global.
    - The cost: a copy of the constant in every module that selects from
      it, even when every selector is constant, and the checks and loads
      at `-O0` (LLVM folds them when optimizing, the global being
      constant and its initializer known).
    - To fix, in the LLVM back end only: in `GenerateExpr`'s designator
      branch, a designator with selectors that `IsConstantExpr` says is
      constant, and whose type is not a record or an array
      (`identity[1]` still needs the global), is emitted as its folded
      value, as on the VAX: of any basic type, not only an integer or a
      set (a `REAL`, `CHAR` or `BOOLEAN` field too), so no copy is made
      unless the constant is passed, selected whole or indexed with a
      variable. A fixture: a local, an imported and a re-exported
      constant, a record field of each basic type, a one- and a
      two-dimensional index, with the IR showing no `-const.` global and
      no index check; the VAX fixture `vax-structured-constant-index`
      already covers a variable index there.
    - Fixed (2026-11-19): `GenerateFoldedSelection`, called from
      `GenerateExpr`'s designator branch, emits such a selection with
      `EmitConstantValue` when `IsConstantExpr` says it is constant and
      its value is neither a record nor an array. Fixture
      `llvm-structured-constant-selection` (a local, an imported and a
      re-exported constant; a field of each basic type; one- and
      two-dimensional indexes) checks the values and that the folding
      procedure's IR has no `-const.` global and no index check, while
      a whole row, a whole field array and a variable index still use
      the copy.

33. **`vax-asts-heap` can count too few collections**. Found
    2026-11-20, in the 0.15.0 gate on atla (`tools/check-hosts`): the
    objects build's run of `AstHeap` printed "collections during the
    run: 2" for the expected "3 or more", twice in `guest-run.com`; the
    fixture passed when rerun alone. How many collections come depends
    on where the 10 ms timer AST falls among the main line's `NEW`s (4
    to 6 seen when it was written), so the count says nothing wrong; the
    program's own checks (bad batches, bad lists) were 0. To fix: have
    the main line run until a number of collections has happened (with a
    limit of passes), or ask for "1 or more", which still shows
    collections while ASTs allocate.

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
    of the new end-of-string null character. [done]
    - Done (2026-11-18): each `OutStr` procedure has a twin, its name
      with `At` added (`CharAt`, `StringAt`, `LnAt`, `IntAt`, `HexAt`,
      `CardAt`, `CardHexAt`, `RealAt`, `LongRealAt`), whose last
      parameter is `VAR pos: LONGINT`, as above. A `pos` outside the
      string, or with no 0X after it, starts the search from the
      string's beginning, as the others do (the user, 2026-11-18); a 0X
      at `pos` is taken for the end without a look before it. The
      others now call their twins. Fixtures `llvm-outstr` and
      `vax-outstr` (in `rtl/vax` too, a copy kept the same).

4.  An Oakwood `Coroutines` module on both back ends [done] (the user,
    2026-11-13; Phase 19's candidate 7, option B of
    `doc/research/concurrency-survey.md`, whose section 8 probed it):
    `Init` and `Transfer`, plus `Free` and `DefaultStackSize`, a hook for
    suspended stacks in each `GarbageCollectedHeap`, a context switch in
    C for x86-64, i386 and arm64 and in MACRO-32 for the VAX, and trap
    statuses 16-18. No compiler change. The plan, eight decisions
    (accepted by the user 2026-11-13) and six phases, the first of them
    probes (pofltk, debuggers, the VAX's quota), is in
    `doc/developer/coroutines.md`. Implemented 2026-11-13 in `rtl/llvm`
    and `rtl/vax` (fixtures `llvm-coroutines-*`, `vax-coroutines-*`),
    with the User's Guide's chapter 11 and the VAX/VMS Guide's
    "Coroutines".

5.  A `Tasks` module on both back ends [done] (the user, 2026-11-14; Phase
    19's candidate 7, option C of `doc/research/concurrency-survey.md`,
    whose section 10 records its probes): cooperative tasks over
    `Coroutines`, the same Oberon source in `rtl/llvm` and `rtl/vax`,
    with Mesa conditions, mutexes, channels, `Select`, `Sleep`, `After`,
    events a signal handler or an AST may post, a replaceable idle step
    (for pofltk), `AwaitReadable`/`AwaitWritable` on POSIX, a
    `TaskInput` module, and trap statuses 19 and 20. No compiler
    change. The plan, fourteen decisions (decided 2026-11-14, Phase 8)
    and seven phases (7-13), is in `doc/developer/tasks.md`; the work
    is on the `tasks` branch. Implemented 2026-11-14 in `rtl/llvm` and
    `rtl/vax` (fixtures `llvm-tasks-*`, `vax-tasks-*`), with the User's
    Guide's chapter 12 and its examples, and the VAX/VMS Guide's
    "Tasks".

6.  Timed descriptor waits in `Tasks` (the user, 2026-11-15, for
    posockets' deadlines and a server's stop, `~/Repos/Oberon/posockets/
    PLAN.md`): `AwaitReadableFor(fd, ms)` and `AwaitWritableFor(fd, ms)`
    return whether `fd` became ready before `ms` passed.
    `doc/developer/tasks.md`, decision 15; fixtures `llvm-tasks-timed`
    and `llvm-tasks-traps`' cases 17 and 18.

7.  System services beyond voc's `Platform` (the user, 2026-11-16, after
    pogemini's rc scripts). A plan: its decisions were accepted by the
    user on 2026-11-16, and revised the same day once poDateTime was
    found to have the clocks. The names were chosen by the user on
    2026-11-16: `StopRequests` for the module and **pounix** for the
    Unix library. All four steps are done (2026-11-16).

    **Why.** The programs built on poc so far each carry C for the same
    operating-system services, because poc can't name `struct stat`,
    `struct sigaction`, `struct passwd`, the `O_*` and `S_IS*` macros
    or `errno` portably across Linux, the BSDs, i386 and amd64:

    | Where | What its C does |
    |---|---|
    | pogemini `GemServer.c` | catches SIGTERM and SIGINT once each, and makes a UTC timestamp by hand |
    | pogemini `GemUser.c` | becomes another user: `getpwnam`, `initgroups`, `setgid`, `setuid` |
    | pogemini `GemFiles.c` | `realpath`, `open` with `O_NOFOLLOW`/`O_NONBLOCK`/`O_CLOEXEC`, a file's kind by `fstat` |
    | polibtls `Tls.c` | a monotonic clock in ms; whether a descriptor is non-blocking |
    | posockets `Sockets.c` | sockets, plus another monotonic clock and ignoring SIGPIPE |
    | polibtls `test/TestPeers.c`, copied as pogemini `test/Child.c` | runs a child process without a shell, waits for it, kills it |

    So some of it is already written twice: the monotonic clock, and
    the child-process helper. The lessons are scattered too: the
    timestamp is made by hand because the first `gmtime_r` loads the
    UTC zone with `tzload`, which needs more than 64 KiB of stack on
    NetBSD and 32 KiB on OpenBSD, more than a task's stack, and
    overran it.

    **Decisions** (accepted by the user 2026-11-16):

    1. **`Platform` keeps voc's interface**, and gets no extension
       module (`PlatformEx`). This is the same reasoning as
       Directories (7e25bbb):
       - its stated purpose is that a program written against voc's
         `Platform` compiles unchanged;
       - Stage 0 is built by voc against voc's own `Platform`;
       - every module in `rtl/` has an implementation in `rtl/llvm`
         and `rtl/vax`.

       A single extension module would also mix services VMS can give
       with ones it can't.
    2. **Portable services become small `rtl` modules, one per concern**,
       each with the same interface in `rtl/llvm` and `rtl/vax`, as
       `Directories` is, **unless a library already gives them**. poc's
       own source doesn't need them, so they need no `rtl/voc` version
       unless that changes. Of the candidates, only stop requests are
       left for `rtl`.
    3. **Services that only make sense on Unix go in a library outside
       poc**, a sibling of posockets, made when a second program needs
       them. It is to be called pounix (the user, 2026-11-16).

    **Clocks: poDateTime, not `rtl`** (revised 2026-11-16). A clock
    module was first proposed for `rtl`. poDateTime
    (`~/Repos/Oberon/poDateTime`, all six steps done, on Linux, the
    BSDs and VAX/VMS 5.5-2) already has one: `Clocks.Monotonic`,
    `Clocks.Now` as an `Instant`, and `TimeStrings`' ISO 8601 and RFC
    3339 forms. So polibtls, posockets and pogemini take poDateTime
    as a dependency instead, in place of their own monotonic clocks
    and pogemini's hand-made timestamp. Its design
    (`doc/date-time-design.md`) settled the VAX's side, which the user
    confirmed from the production VAX they maintain:
    - **VAX/VMS 5.5-2 has no UTC** (Q7, Q22). The system clock is local
      time, set with `$SETIME` at the changes of daylight saving time
      (on the user's VAX, every night from a NIST time server); there
      is no `SYS$TIMEZONE_DIFFERENTIAL`. `Clocks.Now` turns local time
      into UTC through the `TZ` logical's POSIX rule, or, without one,
      `Fixed(0)`, when `Now` is really local time.
    - **The monotonic clock is `EXE$GL_ABSTIM_TICS`** (Q8), 10 ms ticks
      since boot, read through `SYS.STB` by an unprivileged program,
      with its wraps every 497 days counted. Setting the clock doesn't
      move it.

    `rtl/vax/TaskWaiting.Now` still reads `$GETTIM`, so Tasks' deadlines
    on VMS move when the clock is set; that is "Ongoing bug fixing" 22,
    since Tasks can't import a library.

    **To check before the programs move to poDateTime:** that
    `Clocks.Now` and `TimeStrings`' ISO 8601 formatting run in a 16 KiB
    task on NetBSD and OpenBSD. On Unix `Clocks.Now` takes the UTC path
    (`clock_gettime`, no `localtime`); `TimeStrings`' stack use is not
    yet measured. [done 2026-11-16: a probe used up a 16 KiB task's
    stack in 256-byte frames until it hit the guard page, with and
    without `Clocks.Now` and `TimeStrings.Instant`; they cost 3 frames
    on NetBSD and OpenBSD, amd64 and i386, and 6 on FreeBSD and Linux,
    so at most about 2 KiB.]

    **Candidate for `rtl` (decision 2): stop requests**, now
    `StopRequests` (done; below). It would catch the requests to stop and let the program
    ask which came, 0 if none:
    - on Unix, SIGTERM and SIGINT;
    - on VMS, perhaps Ctrl-C or Ctrl-Y through an AST.

    Each is caught only once, so that a second request ends the
    program at once (pogemini's `SA_RESETHAND`).
    - **Waking a task:** an option to post a `Tasks.Event` on a
      request, so that a server waiting in `Tasks` learns of it at
      once. Done through a procedure the program installs, so that the
      module doesn't import `Tasks`.
    - **Rules:** it follows the rules of "Threads and signal handlers"
      (c67aad2) for what a handler may do.
    - **Platform's interface stays:** `Platform.SetInterruptHandler`
      (voc's, SIGINT only) is unchanged.
    - **Users:** pogemini's `GemServer.catch` and `caught`.
    - **VMS:** what VMS offers to match SIGTERM is to be found out.

    **Candidates for the Unix library (decision 3):**
    - becoming another user, all-or-nothing, with a check that root
      can't be regained;
    - running a child process with its arguments as a list, with no
      shell and so no quoting, then waiting for it and killing it.
      pogemini runs `openssl` through `Platform.System`, so through the
      shell;
    - `realpath`, opening with flags, a file's kind, whether a
      descriptor is non-blocking.

    **pounix's first contents: what pogemini's C becomes** (with the
    user, 2026-11-16). The aim is that pogemini keeps no C of its own,
    and that the next program takes these services from pounix rather
    than from a copy of pogemini's C. The services go to pounix; what
    is pogemini's policy stays in pogemini, rewritten in Oberon on
    pounix:
    - **To pounix:**
      - users, all of `GemUser.c`: whether the process runs as root,
        and becoming another user for good (`getpwnam`, then
        `initgroups`, `setgid`, `setuid`, then a check that root can't
        be regained); perhaps also looking up a user's IDs and home on
        its own;
      - `realpath` (`gemfiles_resolve`);
      - files by descriptor, the general part of `GemFiles.c`: opening
        with flags (`O_RDONLY`, `O_NONBLOCK`, `O_NOFOLLOW`,
        `O_CLOEXEC`), a file's kind by `fstat` (regular, directory,
        other), reading into a buffer with `EINTR` retried, closing,
        and a failure's cause as a few kinds from `errno` (no such
        file, not permitted, other);
      - child processes: running a command from a list of arguments,
        with no shell, then waiting for it or killing it, for
        `GemCert`'s `openssl`, which now goes through the shell by
        `Platform.System`. This already has more than one user: the C
        helpers polibtls's `test/TestPeers.c` (`Spawn`, `Wait`,
        `ReadLine`, `Kill`) and pogemini's `test/Child.c`.
    - **Stays in pogemini, in Oberon:** a file must lie under the
      capsule's root once resolved; a hidden name (beginning with ".")
      is never served; which failures count as "not found" for Gemini
      (`EACCES` among them); and the order `GemFiles` relies on:
      resolve, check, then open with `O_NOFOLLOW` in case the last name
      became a link in between.
    - **Not pounix:** `GemAccess`'s `Platform.GetTimeOfDay` moves to
      poDateTime's `Clocks`, missed in step 3; `Platform.getEnv` and
      `Platform.IdentifyByName` are poc's and stay. polibtls's check
      that a descriptor is non-blocking (`Tls.c`) probably stays too,
      rather than make a library depend on pounix for one call.

    Child processes have a second user already, so the trigger in
    decision 3 and step 4, "when a second program needs them", is
    arguably met; the user decided to start pounix at once
    (2026-11-16), as `~/Repos/Oberon/pounix`, with the modules
    `UnixErrors`, `UnixUsers`, `UnixFiles` and `UnixProcesses`.

    Ignoring SIGPIPE stays in posockets, where it matters.

    **To check first:** `Platform.GetClock` calls `localtime`
    (`Platform.c`). Its first call in a task probably overruns a small
    task stack on NetBSD and OpenBSD, as `gmtime_r` did in pogemini.
    If it does, the fix belongs in "Ongoing bug fixing", whatever
    becomes of this plan. Checked 2026-11-16: it does, on NetBSD amd64
    and OpenBSD i386; that is "Ongoing bug fixing" 24, fixed.

    **Steps:**
    1. Choose the names with the user: the stop-request module and the
       Unix library. [done: `StopRequests` and pounix, 2026-11-16]
    2. The stop-request module in `rtl/llvm` and `rtl/vax`, with:
       - fixtures, including one that runs it in a 16 KiB task on the
         BSD hosts;
       - its `rtl/llvm/README.md` entry;
       - the Reference Guide regenerated.

       [done 2026-11-16] `StopRequests`: `none`, `interrupt`,
       `terminate`, `Catch`, `Latest` and `SetNotifier(Notifier)`, a
       `PROCEDURE` called from the handler, which may post a
       `Tasks.Event`.
       - **On Unix** (`StopRequests.c`), `Catch` installs a handler for
         SIGINT and SIGTERM with `SA_RESTART | SA_RESETHAND`, each
         blocking both, and counts the notifier in `Platform.c`'s
         `handlers-running`, so a `Transfer` in it traps as in
         `Platform`'s handlers. It replaces a SIGINT handler
         `Platform.SetInterruptHandler` set, and the reverse.
       - **On VMS** it is `Platform.SetInterruptHandler` with its own
         handler, which takes itself away, so the next CTRL/C acts as
         CTRL/Y. `terminate` is never reported there: what matches
         SIGTERM on VMS is still to be found out.
       - **Fixtures:** `llvm-stop-requests` raises SIGINT from a 16 KiB
         task, waking another awaiting the posted event, then SIGTERM,
         SIGINT after `Catch` again, and the SIGINT after that, which
         ends the program (status 130); under `-O2` and `-OC`.
         `vax-stop-requests` runs on the guest over telnet, so with the
         AST armed on a terminal. Nothing there types CTRL/C, so it
         checks only that `Latest` stays `none` and the program ends
         normally. A caught CTRL/C on VMS is not yet tested.
    3. polibtls, posockets and pogemini move to poDateTime's clocks
       (after the 16 KiB check above) and to the stop-request module
       in their next release. This raises the poc they need to the
       release that has the module, so do it when they need a new poc
       anyway.

       [done 2026-11-16, with poc 0.14.0 and poDateTime 5ae9a47] Each
       now needs poDateTime, installed by the same poc, and stops
       `make` with a message (pogemini's `make deps`) without it.
       - **polibtls** (cfb12e0): connections' deadlines take
         `Clocks.Monotonic`, in place of its own `CLOCK_MONOTONIC`; its
         example GeminiHello stops on SIGINT or SIGTERM through
         `StopRequests`, finishing its connections, which `TestGemini`
         checks with a request in progress.
       - **posockets** (08b6e48): `Sockets.Now`, and so the deadlines,
         take `Clocks.Monotonic`; its least poc stays 0.13.0.
       - **pogemini** (bc1aa0d): `GemServer.c` is gone. `Listen` calls
         `StopRequests.Catch`, and the log's time is `Clocks.Now` and
         `TimeStrings.Instant`, in the same format.
       Each passed its tests on Linux (polibtls and posockets under
       valgrind as well) and on all five BSD hosts.
    4. The Unix library, as a project of its own, when the next program
       needs one of its services.

       [done 2026-11-16, with poc 0.14.0] pounix
       (`~/Repos/Oberon/pounix`, its PLAN.md), with the modules
       `UnixErrors`, `UnixUsers` (`Root`, `Become`), `UnixFiles`
       (`Resolve`, `OpenRead`, `KindOf`, `Read`, `Write`, `Close`) and
       `UnixProcesses` (a command as a list of arguments, with no
       shell; `Start`, `Wait`, `Signal`, pipes):
       - **pounix** (c6070a7): Phases 1 to 6. Each module is tested on
         Linux and checked under valgrind. `gmake test` and the
         root-only test pass on all five BSD hosts. `make install` was
         checked by building README's example from an installed copy.
         Two differences between systems were found, both in the tests:
         - A FIFO no writer has yet opened reads as `EAGAIN` on
           FreeBSD, and as the end of the file on the other systems.
         - FreeBSD and OpenBSD have no `/proc/self/fd`, so the
           close-on-exec checks now ask a child shell to redirect from
           the descriptor instead.
       - **pogemini** (dbf5250) keeps no C of its own:
         - `GemUser` gives way to `UnixUsers`, and `GemFiles.c` to
           `UnixFiles`. The rules for serving files are unchanged, now
           in Oberon: under the root once resolved, no hidden name, the
           same failures counted as "not found", and the file opened
           without following a final link. The root and hidden-name
           checks were each tested by taking them out, which made
           TestFiles fail.
         - `GemCert` runs `/bin/sh` through `UnixProcesses`, with a
           fixed script and its values as `$1` to `$3`, in place of a
           quoted command line through `Platform.System`. So a
           certificate directory may now have `'` in its name.
         - `GemAccess`'s `Platform.GetTimeOfDay` became `Clocks.Now`
           and `Instants.UnixSeconds`, as planned above (not pounix).

         pogemini passed `make test` on Linux (299 checks) and on all
         five BSD hosts.

       Not moved, and why:
       - The test helpers that start child processes, polibtls's
         `test/TestPeers.c` and pogemini's `test/Child.c`, could use
         `UnixProcesses`. But `TestPeers.ReadLine` and pogemini's tests
         need a wait with a time limit, which pounix doesn't offer: it
         is one of pounix's open questions, until a user asks.
       - polibtls's `Tls.c` (whether a descriptor is non-blocking)
         stays, as expected above, so polibtls doesn't depend on pounix for one
         call.

8.  `In.Peek` (the user, 2026-11-19, for pounicode's
    `Utf8Files.InRune`, `~/Repos/Oberon/pounicode`): the next byte of
    standard input, without consuming it. [done]
    - Done (2026-11-19): as proposed, in `rtl/llvm/In.Mod` and
      `rtl/vax/In.Mod`, named in both head comments and in
      `rtl/llvm/README.md`. Fixtures `llvm-in-peek` (each case below,
      the 0X byte included, and `Peek` before `Int`) and
      `vax-in-peek` (the same program, a `y` for the 0X byte, which a
      VMS text record sent by FTP cannot be counted on to keep).

        PROCEDURE Peek*(VAR ch: CHAR);
        BEGIN
          IF input.Ready() THEN ch := nextch; Done := TRUE
          ELSE ch := 0X; Done := FALSE
          END
        END Peek;

    - Why: a UTF-8 decoder must read the byte after a lead byte to
      learn whether the sequence goes on. Given `E2 'x'`, `InRune`
      should return U+FFFD and leave the `x` for the next read, as
      Go's `bufio.Reader.ReadRune` and pounicode's `ReadRune` on a
      `Files` rider (which `Set`s back) do. `In.Char` is the only way
      to read a byte, so the `x` is consumed. Without `Peek`,
      `Utf8Files` must keep a one-byte pushback of its own, which is
      lost to a program that calls `In.Char` or `In.Line` after an
      invalid sequence.
    - Cost: `In` already reads one byte ahead (`nextch`, `readstate`),
      and its private `StandardInput.Ready` and `Current` already do
      the work. `Peek` is a call and a test of `readstate`: no new
      buffering, no extra `getchar`, and no change to the other
      procedures.
    - Blocking: at the start or after a line end (`readstate =
      pending`), `Peek` must call `getchar`, so on a terminal it waits
      for the next line, as any reader would to answer the question.
      `InRune` only peeks after a lead byte, where `Advance` has
      already read the next byte, so correct input never blocks
      earlier than with `In.Char` alone.
    - End of input: `Done` is FALSE and `ch` is 0X, as with `In.Char`,
      so a real 0X byte (`Done` TRUE) is told apart from the end.
    - Both back ends: `rtl/vax/In.Mod` has the same `nextch` and
      `readstate` lookahead, so the procedure is the same there.
    - Not in Oakwood or voc's `In`: it is an addition, like `Card` and
      `HugeCard`, and goes in the module's head comment and
      `rtl/llvm/README.md`.
    - Fixture: `Peek` then `Char` on the same byte; `Peek` twice; `Peek`
      at the end (Done FALSE); a 0X byte (Done TRUE); a line end, then
      `Line`.

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

Those done while Phase 17 was current, 3, are in
`doc/history/phases/phase-17.md`.

4. **External variables** [done] (decided 2026-10-28, `000-todo.org`): `VAR
   ["C", "environ"] environment-: SYSTEM.ADDRESS;` names storage another
   language defines, read and written in place, in place of an external
   procedure's address and `SYSTEM.GET`/`PUT`. Proposals E1-E8 in
   `doc/developer/language-extensions.md`, "External variables",
   approved by the user 2026-10-28 with the attribute on each
   declaration, and implemented for both backends (fixtures
   `llvm-external-variable`, `semantic-reject-external-variable`,
   `vax-external-variable`).

5. **Predeclared unsigned types** [done] (decided 2026-11-01, `000-todo.org`):
   `SHORTCARD`, `CARDINAL`, `LONGCARD` and `HUGECARD`, as wide in each size
   model as `SHORTINT`, `INTEGER`, `LONGINT` and `HUGEINT`, a family apart
   with the rules of `SYSTEM.CARDn`, which stay. A program with no `SYSTEM`
   import also needs a way across the families and a way to read one, so
   the plan adds a predeclared `VAL(T, x)` and `In.HugeCard`, accepted by the
   user 2026-11-01. The plan, its six steps and what they change are in
   `doc/developer/predeclared-unsigned-types.md`. Done 2026-11-01, on both
   backends (fixtures `semantic-predeclared-cardinal`,
   `semantic-strict-predeclared-cardinal`, `semantic-reject-predeclared-val`,
   `llvm-predeclared-cardinal`, `llvm-predeclared-cardinal-import`,
   `llvm-predeclared-val`, `vax-predeclared-cardinal`,
   `vax-predeclared-val`).

6. **Indexing a string constant** [done] (found in polibtls, 2026-11-15, poc
   0.13.0; recorded 2026-11-19): with `CONST certs = "..."`, poc refuses
   `certs[i]` ("'[' requires an array or a pointer to an array") and
   `LEN(certs)`, and polibtls passes the constant as a value `ARRAY OF
   CHAR` parameter to index it. `Oberon2.pdf` does not allow it (§8.1
   indexes only an array; a string constant is not one), nor does voc
   (err 79, err 131). Proposals S1-S8 in
   `doc/developer/language-extensions.md`, "Indexing a string constant":
   the constant read as a read-only `ARRAY m+1 OF CHAR`, `s[k]` folded,
   `s[i]` index-checked, `LEN(s)` the constant `m+1`, `-strict` rejecting
   both; approved by the user and implemented 2026-11-19, on both back
   ends (fixtures `llvm-string-constant-index`,
   `semantic-reject-string-constant-index`,
   `semantic-strict-string-constant-index`, `vax-string-constant-index`).

## Ongoing implementation enhancements

Changes to how poc builds, links and packages programs and libraries that
using poc on other programs shows are wanted, made as they come,
alongside whichever phase is current. Each item says where the need was
found and what was decided with the user, and is marked `[done]` once it
is committed with its fixtures, `make check` passes on Linux and the
three BSDs, and the User's and Reference Guides and poc(1) say what it
does; a done item stays until the next phase's close-out, which moves it
to that phase's record. Made on `main` (and, for the VAX, on the `vax`
branch until it was merged into `main`, 2026-10-17).

Those done while Phase 15 was current, 1-4, are in
`doc/history/phases/phase-15.md`.

Those done while Phase 18 was current, 5-7, are in
`doc/history/phases/phase-18.md`.

8.  poc on VAX/VMS needs less memory and a smaller working set (the
    user, 2026-10-22; left open by Phase 16): what holds poc's memory,
    and the plan to reduce it in seven steps, measuring first, are in
    `doc/developer/vms-memory.md`.

9.  Linking what poc did not compile (the user, 2026-10-27;
    `000-todo.org`): a program or library can be linked with objects and
    libraries of other languages on every target.
    - `-link <line>` for vax-dec-vms [done]: each argument a line of the
      Linker's options file, in programs' and libraries' links, and
      recorded in a library's manifest as on LLVM
      (`doc/developer/vax-macro32-backend.md`, section 13). Fixture
      `vax-link`, run on the guest.
    - `-target vax-dec-vms` on Unix refuses the options only the LLVM
      back end has, as poc on VMS does, rather than ignoring them (the
      user, 2026-10-27) [done]. Fixture `poc-vax-target-llvm-options`.
    - Object files named on the command line, `.o` on Unix and `.obj` on
      VMS, linked into the program or put in the library [done]: designed
      (2026-10-27) in seven proposals, 1-4 and 7 in
      `doc/developer/llvm-toolchain.md`, "Object files on the command
      line", 5 and 6, the VAX's, in `doc/developer/vax-macro32-backend.md`,
      section 13.1. The guest showed (2026-10-27) that a VMS object
      fetched by FTP in binary loses its record boundaries, so on Unix
      poc takes only a counted-form object and refuses others; and a
      VAX library reads an object's global symbols to make them
      universal (the user, 2026-10-27). LLVM first, then the VAX. The
      LLVM side, 1-4 and 7, is done (2026-10-27; fixture
      `poc-object-files`); the VAX's 5, `-build`, too (2026-10-27;
      fixture `vax-build-object-files`); and 6, `-library`, too
      (2026-10-27; fixture `vax-library-object-files`, run on the guest),
      the entry points read from the object's GSD records by
      `ObjectRecords.Open` and `Get`, VMS's over `RecordFiles`' below.
    - A program on VMS that writes an object in the counted form, the
      reverse of OBJCONVERT (the user, 2026-10-27) [done]: `OBJCONVERT
      -COUNTED <object> <counted file>` reads the object's records and
      writes each as its count, its bytes and a pad byte after an odd
      count, into a file of fixed 512-byte records, so that FTP in
      binary brings to Unix what poc's `-build` takes there; the zeros
      after the last record end a counted file. Six proposals, approved
      and done 2026-10-27 (`doc/developer/vax-macro32-backend.md`,
      section 13.2), with `RecordFiles.Open`, `Get` and `CreateFixed`.
      Fixtures `vax-objconvert-counted`, run on the guest, and
      `vax-build-object-files`.
    - Options files named on the command line for vax-dec-vms, `.opt`
      among `-build`'s or `-library`'s files (proposal 9, approved by
      the user 2026-10-28, "recorded like -link") [done]: poc reads each
      and adds its lines after the `-link` arguments, as `-link`'s, so a
      library's manifest records them and every program linked with the
      library gets them; blank and comment lines left out, a line ending
      in `-` joined with the next (`doc/developer/vax-macro32-backend.md`,
      section 13.3). The guest showed first (2026-10-28) that a recorded
      `PSECT_ATTR` line is harmless in a program that does not need it.
      Fixture `vax-options-files`, run on the guest.

10. Libraries without a shared object [done] (the user, 2026-10-31; found
    by pofltk, whose `make install` fails where FLTK is static libraries
    built without `-fPIC`): `poc -library` always linked a shared object,
    and that step failed before the manifest was written. What that
    implies, the `-no-shared-library` option, built in nine steps, and
    how pofltk detects when to pass it are in
    `doc/developer/static-only-libraries.md`. poc's part, steps 1-7, is
    done with fixture `llvm-library-no-shared`, the release, step 8, was
    0.11.0, and pofltk's part, step 9, is pofltk's `c1e03a8`.

11. A VMS site rebuilds poc through the object back end [done] (the user,
    2026-11-06, while installing 0.11.1 in `DUA1:[POC]`): after `@BUILD`
    has made `POC.EXE` from the kit's MACRO-32, a new procedure in the
    base kit, `BUILDVIAOBJ.COM`, has that poc compile its own source in
    `[.SRC]` and link a new `POC.EXE` from the objects it writes, with
    only the runtime's `[.SRC.RTL]POCRTL.MAR` assembled by `MACRO`. The
    kit already carries every source file this needs, so the procedure
    is the only new file. Today a site can do it only by hand, as the
    VAX/VMS Guide's "Building poc from its source on VMS" says; `make
    vax-stages` reaches the objects' fixed point on the guest, but from
    a V1 cross-compiled on Unix, not from a kit's poc; and `make
    check-vax-kit CHECK_VAX_KIT_FLAGS=-full` compiles `[.SRC]` with the
    kit's poc, but under `-vax-macro32`. Nothing yet builds poc from a
    kit's poc through objects. What was proposed to the user, 2026-11-06,
    each point still to be settled with them:
    - **It runs only after `@BUILD`:** it refuses unless `[.BIN]POC.EXE`
      exists and `POC -VERSION` names the kit's version (`VERSION.TXT`).
    - **It writes the arguments itself:** `FULL.ARGS` as the guide has
      it (`-OC`, since poc needs a 64-bit `LONGINT`;
      `-clear-library-path`, from source alone; the seven `-import-path`
      directories; `-build [-.SRC.DRIVER]POC.MOD`), in a directory of its
      own, such as `[.OBJBUILD]`, then `POC @FULL.ARGS` and `@POC`.
    - **It leaves the installed poc alone** unless asked: the new
      `POC.EXE` stays in its own directory, and only a parameter such as
      `INSTALL` copies it to `[.BIN]`, keeping the old one, and only
      after the check below has passed, so that a failure part way
      leaves a working poc.
    - **A fixed-point check, `CHECK`:** the new `POC.EXE` compiles the
      same source again, and the two sets of objects must be the same.
      As in `vax-stages`, both run under one `SOURCE_DATE_EPOCH` (a
      logical name), so that the objects' creation times in their MHD
      records agree (`doc/developer/vax-object-language.md`); how to
      compare objects on VMS alone, without `tools/vax-objects.sh`'s
      DUMP/RECORDS on Unix (perhaps `DIFFERENCES` or `CHECKSUM` of each
      object), is to be found on the guest. Each compilation takes about
      45 minutes on the SIMH VAX, so `CHECK` doubles the time.
    - **It checks the process's quotas first:** poc compiling itself
      peaks at about 15.5 MB, and a low `PGFLQUOTA` makes it trap with
      `%X10000022` (POC2, 2026-10-16), so the procedure reads the quota
      and says what is needed before it starts, not an hour in.
    - **It prints its times,** as `BUILD.COM` does.
    - **Made and checked by the kit's tools:** `tools/bootstrap/
      make-vax-kit` puts it in the base kit beside `BUILD.COM` and
      `SETUP.COM` (from `tools/bootstrap/vax-kit/`), and `check-vax-kit
      -full` runs `@BUILDVIAOBJ CHECK` in its scratch tree, so every
      release checks it.
    - **Documented:** the VAX/VMS Guide's chapter 1 names it as a step
      after `@BUILD`, for a site that wants it; "Building poc from its
      source on VMS" leads with it, keeping the commands by hand as what
      it does; Appendix A lists it among the base kit's files; the kit's
      `README-VMS.TXT` names it.
    - **Released in 0.12.0,** not 0.11.1, whose kits are published
      without it; the 0.12.0 release notes say how to use it.
    Separate from `BUILD.COM` (rather than `@BUILD OBJECTS`), since
    `BUILD.COM` builds poc where there is none, and this one needs the
    poc it built.

    **Made, 2026-11-06/07** (the user's go-ahead, 2026-11-06), as
    proposed, with these findings and choices:
    - **`@BUILDVIAOBJ [CHECK|INSTALL]`:** one parameter, `INSTALL`
      doing the check too, so nothing is installed unchecked. It also
      refuses unless `[.SRC.DRIVER]POC.MOD` is there, and checks the
      new image's `-VERSION` before going on. `INSTALL` keeps `@BUILD`'s
      image as `[.BIN]POC-KIT.EXE` (once: a second `INSTALL` keeps the
      first), copies the new one as the next version of `POC.EXE`,
      which takes the old one's protection, and purges it.
    - **Comparing objects on VMS:** `DIFFERENCES` cannot do it, since its
      `$STATUS` is `%X006C8009` whether the files differ or not (found
      on the guest, 2026-11-06). The procedure compares each object, and
      `POC.COM`, by `CHECKSUM`'s `CHECKSUM$CHECKSUM` and by `EOF` and
      `FFB`, and counts that `[.OBJCHECK]` has as many objects.
    - **`SOURCE_DATE_EPOCH`:** the logical name when it is defined, else
      the time the procedure starts, worked out in DCL (days from the
      civil date by 400-year eras), the clock's time taken as UTC; on
      the guest it gave 1794008478 at 6-NOV-2026 23:41:18, which `date
      -u -d @1794008478` agrees with. The kit cannot carry the commit's
      time, since a kit made from a tarball has no git.
    - **The quota:** 60,000 pages of `PAGFILCNT` left (the heap is three
      quarters of it, and poc's peaks at about 16 MB). The guide's
      chapter 17 still said 90 MB, from before the memory work of
      2026-10-24; corrected. README.TXT also said `POC @FULL.ARGS`
      writes MACRO-32, which it does only with `-vax-macro32`; corrected.
    - **Documented** in README.TXT (a step 5), not README-VMS.TXT, the
      STARLET kit's, which has nothing to say of it; and in
      `tools/bootstrap/README.md`.
    - **`check-vax-kit -full`** runs `@BUILDVIAOBJ INSTALL` after its
      MACRO-32 fixed point, then `@SETUP`, `POC -VERSION` and the `-O2`
      KITHELLO with the installed poc; its default timeout is now 25,200
      seconds.
    - **Checked on the guest** (2026-11-06/07, POC's account, a scratch
      `[.BVOTEST]`, the kit from the working tree): it refused before
      `@BUILD` and refused `BOGUS` (`%X10000014`); `@BUILDVIAOBJ INSTALL`
      built `[.OBJBUILD]POC.EXE` in 14.5 minutes (859 s of CPU), found
      all 44 objects and `POC.COM` the same in `[.OBJCHECK]` (14 minutes,
      840 s), and installed it; poc so installed said its version and
      built and ran a program. `check-vax-kit -full` then passed on
      `0388813` (2026-11-07): the MACRO-32 fixed point, `@BUILDVIAOBJ
      INSTALL` (13.5 minutes, 809 s, and 13.5 minutes, 811 s), and
      KITHELLO from the installed poc, in about an hour in all. Released
      in 0.11.2.

12. The examples as source, for a VMS site with poc installed [done] (the
    user, 2026-11-15): a second kit of the VAX/VMS Guide's examples,
    `POC-EXAMPLES-SOURCE-<version>.COM` (`make examples-vax-source`,
    `tools/build-examples-source`), holds their Oberon-2 source rather
    than MACRO-32 poc wrote on Unix, so that a site can change a program
    and build it again with the installed poc, the foreign command `POC`,
    through its object back end. Its `BUILD.COM` builds each program
    whose `.EXE` is missing or older than its `.MOD` (or Shell's
    `.CLD`), by revision date, with the options the guide gives it
    (Fail `-TRAP-LOCATION`, Shell `SHELLCOMMANDS.CLD`); `@BUILD ALL`
    builds every one and `@BUILD NAME` that one. Run again, the kit
    unpacks only the files that are missing, so a changed source is
    kept. It is a release file beside `POC-EXAMPLES-<version>.COM` (`make
    dist`, `tools/release-files`). Both kits now also hold the User's
    Guide's coroutine programs `Queens` and `WordSets`, with `WordSets`'
    `memo.txt` and `words.txt`, which the VAX/VMS Guide names and which
    run there unchanged; in the MACRO-32 kit they link
    `COROUTINESWITCH.OBJ`, as `TaskMailbox` does.
    - **Checked on the guest** (2026-11-15, user TKB, poc 0.12.0
      installed, scratch directories since deleted): the source kit
      unpacked its files, `@BUILD` built all 21 programs, and again built
      none; the kit with `Queens` and `WordSets` added, run again there,
      kept the 23 files and unpacked the four new ones; after a line was
      appended to `HELLO.MOD`, `@BUILD` built just `HELLO`, `QUEENS` and
      `WORDSETS`. The MACRO-32 kit, in an empty directory, built all 23
      programs. `HELLO`, `QUEENS` and `WORDSETS` ran as the guides show
      from both.

13. Investigate: the collector turning off valgrind's error reporting
    while it collects [done] (the user, 2026-11-18; found in posockets and
    polibtls, putting their task tests under full memcheck now that
    bug 21 is fixed). The collector scans stacks conservatively, a
    coroutine's included, so memcheck reports the words it reads that
    were never written. Most of these reports are in `MarkCandidate`,
    which each project's `poc-gc.supp` suppresses. But when such a
    word happens to point at a live, unmarked block, the block is
    pushed and memcheck reports `Value8` in
    `GarbageCollectedHeap.DrainMarkStack` / `TraceBlock`. posockets'
    `TestFileServer` has 22 of these every run
    (`--track-origins`: stack allocations in `SocketTasks.Await` and
    `TestFileServer.Whole`), and it now needs a suppression file of its
    own (`test/TestFileServer.supp`).
    - The same `DrainMarkStack` report was thought a real bug elsewhere:
      a record copied whole from the stack into the heap carrying its
      uninitialised padding (pogeminilib, Phase 2). So the projects
      keep it out of their shared `poc-gc.supp`. That diagnosis was
      wrong: SROA had taken the record apart, and the words were
      `Take`'s spill slots, read by the stack scan
      (`doc/developer/collector-under-valgrind.md`).
    - The idea: wrap a collection in `VALGRIND_DISABLE_ERROR_REPORTING`
      / `VALGRIND_ENABLE_ERROR_REPORTING` (`rtl/llvm/valgrind.h`, as
      `Coroutines.c` already uses for bug 21). Or mark each word as
      defined before testing it as a candidate
      (`VALGRIND_MAKE_MEM_DEFINED` on a copy).
    - To investigate:
      - whether either change keeps memcheck reporting padding copied
        into the heap, which the program reads (outside the
        collector), while dropping the scan's own reports;
      - what it costs outside valgrind (the client requests are a few
        instructions when not under valgrind);
      - whether the projects' `poc-gc.supp` files and
        `TestFileServer.supp` can then go.
    - Done (2026-11-18): under valgrind the stack scan (`MarkFromStack`,
      and `MarkRange` for coroutines) reads each word through
      `GarbageCollectedHeap.c`'s `DefinedWord`, which copies it and
      marks the copy defined (`VALGRIND_MAKE_MEM_DEFINED`), so memcheck
      reports nothing the scan reads and still reports every other use
      of an undefined value; turning reporting off would hide errors
      during a collection too. `UnderValgrind` is asked once; natively
      GcBench runs 0.1% more instructions. `rtl/llvm/memcheck.h` is
      valgrind 3.27.1's. Fixture `llvm-gc-valgrind`; pogeminilib's
      `TestText` (whole-record copy restored) went from 700,877 errors
      to 0, posockets' `TestFileServer` from 977 to 0, with no
      suppressions. `doc/developer/collector-under-valgrind.md` has
      the account.
    - After a release with it: the projects drop their collector
      suppressions (`test/poc-gc.supp` in pofltk, pogeminilib,
      polibfyaml, polibtls, posockets and pounix, poDB's entries in
      `test/valgrind.supp`, posockets' `test/TestFileServer.supp`),
      and pogeminilib copies the record whole again and corrects its
      note about padding.

14. Structured constants re-exported, and the copies of them each module
    makes [not to be done until a program shows the cost] (the user,
    2026-11-19; a test of re-exporting, M3 exporting
    `origin* = Point{...}` and `identity* = Matrix{{1, 0}, {0, 1}}`, M2
    re-exporting them as `origin* = M3.origin`, M1 printing
    `M2.origin.x` and `M2.identity[1,1]`). It works, and the constants
    have no storage of their own, by design
    (`doc/developer/record-and-array-literals.md`, "In memory"): neither
    M3.o nor M2.o defines a symbol for them, M2.sym carries the value
    folded to its literal, `origin* = M3.Point{x := 0, y := 0}`, not a
    reference to M3's, and M1 makes its own `@M1.-const.<n>`, a private
    constant global. A re-export is an alias of the value, not of a
    location; as a constant has no address, nothing can tell. What the
    test showed could be better:
    - **A selector with constant operands is not folded in a statement.**
      `M2.origin.x` and `M2.identity[1,1]` load from M1's copy, with a
      run-time index check on constants. It is a bug, not the
      re-export's, and not only an imported constant's: "Ongoing bug
      fixing", 32.
    - **One module can hold two copies of one constant.**
      `StructuredConstGlobal` (`src/back/llvm/LLVMCodeGenerator.Mod`)
      shares a global by the `Types.Value` it holds, and `M3.origin` and
      `M2.origin` are two values read from two .sym files, so a module
      using both gets `@M5.-const.1` and `-const.2`, equal. Share them by
      type and contents instead. (`unnamed_addr` lets LLVM merge them
      when optimizing; this is about `-O0` and the VAX.)
    - **To decide with the user: one copy for the program.** Each
      importer that needs memory still has its own. A shared one would
      be a `linkonce_odr` global with a name from the exporting module
      and the constant (`@M3.origin`, kept in a comdat), which a
      re-exporter's .sym would have to name back to M3; or the exporter
      would define it, and an importer would then link to it, as now it
      does not. Small constants likely do not repay that; a large table
      used in many modules might. Either way the .sym keeps the value,
      so the compiler folds what it can as now; the shared global is only
      the copy in memory, for passing the constant or indexing it with a
      variable.
    - **Not to be done until a program shows the cost** (the user,
      2026-11-19). Once bug 32 is fixed, a copy is made only for a
      constant passed, selected whole or indexed with a variable;
      `unnamed_addr` lets LLVM merge equal copies when optimizing, and
      across modules under `-lto`; and one copy for the program would
      tie a re-exporter's .sym to the exporter's and need its own design
      on the VAX, whose object language has no comdat. Bug 32 is fixed
      on its own, under "Ongoing bug fixing".

15. A `NEW` the heap cannot satisfy always traps, with hooks (the
    user, 2026-11-20; found in podoc, `~/Repos/Oberon/podoc`, which is
    built with `-trap-heap-exhausted`). Decided with the user the same
    day; not yet started. Replaces the first proposal of that day, kept
    below as the alternative considered.
    - **The need.** `-trap-heap-exhausted` makes the code generated
      after each call to `GarbageCollectedHeap.Allocate` test the result
      and trap 11 at that `NEW`'s line and column
      (`LLVMCodeGenerator.trapHeapExhausted`, `EmitHeapCheck`;
      `VaxCodeGenerator.trapHeapExhausted`). So it covers only the
      modules compiled with it. A `NEW` in an installed library built
      without it, the runtime's or the user's, still leaves NIL, and the
      program stops later with "NIL pointer dereference", away from the
      cause. podoc allocates much of its memory in Ropes, so its clear
      message depends on where the heap happens to run out.
    - **Shown with poc 0.15.0 on atla.** A test program with a 4 MB heap
      limit (`SetHeapLimit`): its own `NEW` gave "heap exhausted: NEW
      cannot allocate the block"; a `NEW` inside the installed Ropes
      gave "NIL pointer dereference"; Ropes compiled from source with the
      option gave the message. podoc on a 45 MB input gave the message,
      exit status 11, from one of its own `NEW`s.
    - **Decided: `Allocate` always traps.** It traps 11 itself whenever
      it finds no memory, in every program, so every `NEW` and
      `SYSTEM.NEW` is covered whatever its module was compiled with.
      That includes the early `RETURN 0` for a size below 0 or above
      `maxObjectSize` (an open array too large for any heap). The trap
      is a procedure of its own in the runtime,
      `GarbageCollectedHeap.OutOfMemory` (the user, 2026-11-20), not
      inline code, so a debugger can stop in it (see the traceback
      below).
    - **Decided: a list of hooks**, added with `AddOutOfMemoryHook` (the
      name the user chose, 2026-11-20). A library that keeps a cache can
      register a hook to free it without knowing what other libraries
      registered:
      ```
      TYPE OutOfMemoryHook* = PROCEDURE (size: SYSTEM.ADDRESS): BOOLEAN;
      PROCEDURE AddOutOfMemoryHook*(hook: OutOfMemoryHook);
      PROCEDURE RemoveOutOfMemoryHook*(hook: OutOfMemoryHook);
      ```
      - **The table.** The hooks are kept in a fixed table of 16
        entries (the user, 2026-11-20) in `GarbageCollectedHeap`, since
        the runtime cannot allocate when the heap is full. Adding to a
        full table is trap 15, the smallest status no trap has (the
        user, 2026-11-20; traps use 2 to 14, reference-guide.md's
        table), with a message such as "AddOutOfMemoryHook: the table
        of hooks is full", since a bare `HALT` prints nothing. Adding a
        hook already there, or removing one that is not, does nothing.
      - **The call.** When `Allocate` finds no memory after its final
        collection, it calls the hooks newest added first, passing the
        size asked for. A hook answers TRUE when it has made room (freed
        a cache and dropped its pointers, or raised the limit with
        `SetHeapLimit`); `Allocate` then collects and tries again. If
        that succeeds, the `NEW` succeeds; if not, the next hook is
        called. Each hook is called at most once per failing `NEW`. When
        every hook has answered FALSE, or there are none, the program
        traps. A hook may also not return: one that writes its own
        message and calls `Platform.Exit`.
      - **The hooks must not allocate.** `Allocate` called again while a
        hook runs traps at once, without calling the hooks, rather than
        recurse.
      - **Order.** The hooks run after `Allocate`'s final collection (so
        they see the heap as full as it is) and before the finalizers,
        which run at `exit` (`FinalizeAtExit`), as for every trap.
    - **Decided: `-trap-heap-exhausted` goes away entirely.** poc no
      longer accepts it (`Poc.Mod`, the two code generators'
      `trapHeapExhausted` and `EmitHeapCheck`, the users-guide and
      reference-guide text, the tests). A makefile that passes it fails
      on the release that removes it, so the release note says so; podoc
      drops it from its `POCFLAGS` and adds its hook in the same change.
    - **The documented contract changes.** reference-guide.md:696 says a
      `NEW` the heap cannot satisfy leaves NIL; that becomes trap 11
      always. A program that tests for NIL after `NEW` gets the trap
      instead, and must add a hook to recover. A release-note item.
    - **With item 16.** Item 16 decides when `Allocate` gives up; this
      item decides what happens then.
    - **podoc** will add a hook that writes "podoc: out of memory; set
      PODOC_HEAP_LIMIT (megabytes) higher" and exits 11.
    - **Decided: the traceback, ways 1 and 2.** A trap raised in
      `Allocate` is no longer at the `NEW`, so its message cannot name
      the site as the per-site check did. Today every trap is inline
      `write` and `exit` (`EmitTrapAt`); poc has no stack walking, and
      emits no `"frame-pointer"` attribute. What follows was read in the
      source; none of it has been tried.
      1. **Under a debugger.** With the trap in its own runtime procedure
         and `-g`, which links the runtime with debug information,
         `break GarbageCollectedHeap.OutOfMemory` in gdb or lldb gives
         the whole backtrace with source lines. A paragraph in
         users-guide §8, and in the reference guide's trap 11.
      2. **The caller's address in the message.** `Allocate` takes its
         return address with `llvm.returnaddress(0)` (declared as the
         collector already declares `llvm.eh.unwind.init`, if the
         intrinsic's constant argument passes through a `["C"]` call; to
         check) and the trap appends it: "heap exhausted: NEW cannot
         allocate the block (at podoc+0x4a3f10)". Under PIE the address
         is printed as an offset from the executable's base, found with
         `dladdr` (in the C library on glibc 2.34 and later and the
         BSDs, `libdl` before; to check on each). `addr2line -f -e podoc
         0x4a3f10` then gives the procedure, and with `-g` the line. It
         costs nothing until the trap. The address is in the procedure
         holding the `NEW` only if `NEW` calls `Allocate` directly; a
         `NEW` that goes through a helper would name the helper. To check
         in the IR.
      Not built: the site's "file:line:column" stored before each call
      under `-trap-location` (a store per `NEW`, only in modules compiled
      with the option, and the option it hung off is gone), and a full
      traceback with `backtrace` (`execinfo.h`; `libexecinfo` on FreeBSD
      and NetBSD, OpenBSD unknown; Oberon procedures come out as
      addresses without `-rdynamic`). A program's hook can do the latter
      if it wants.
    - **Decided: the VAX too.** `rtl/vax/GarbageCollectedHeap.Mod` has
      the same `Allocate` structure, so the trap, the hook table and the
      calls carry over. The failing `NEW`'s site comes from VMS's own
      symbolic traceback (the user, 2026-11-20). What follows was read
      in vax-vms-guide.md ("A fault and its traceback") and
      reference-guide.md's VAX/VMS trap paragraph, not tried.
      - **VMS prints a symbolic traceback itself.** A severe condition
        that no handler takes reaches VMS's last-chance handler, which
        prints the message and the calls newest first: module, routine,
        line and PC. poc's objects carry the traceback records (TBT
        DSTs) for this with no `/DEBUG`; a program built from MACRO-32
        gives poc's VAX symbols and no line. Better than Unix's address
        and `addr2line`, with no saved PC or link map needed.
      - **But traps don't signal today.** A poc trap on VMS writes its
        message and `$EXIT`s with `%X10000000 + 8*c + 2` (severity
        error, DCL's message suppressed), so no traceback is printed.
      - **So on VMS `OutOfMemory` calls `LIB$STOP`**, which prints the
        message and the traceback and ends the program; exit handlers,
        and so the finalizers, still run. The condition is
        `POC$_HEAPEXH`, from poc's own message file (item 17): VMS then
        prints "%POC-F-HEAPEXH, heap exhausted: NEW cannot allocate the
        block". Until item 17 is done, `LIB$_INSVIRMEM` ("insufficient
        virtual memory"), a system condition with a real message; poc's
        own number without a message file would print a "NOMSG" message.
        Either way the status is not the trap convention's
        `%X1000005A`: `LIB$STOP` makes the severity fatal.
    - **The alternative considered** (2cdad0b, the first proposal). When
      the main module is compiled with `-trap-heap-exhausted`, the `main`
      it defines sets a flag in `GarbageCollectedHeap` before any module
      body runs, as it already calls `Modules.Init` and records the stack
      base there (not in the main module's body: bodies run in import
      order, the main module's last, and the libraries' bodies allocate
      before it). With the flag set, `Allocate` traps 11 itself; the
      per-site check stays, for the location. Set aside because it keeps
      NIL as the default, which few programs handle, and because hooks
      let a program choose its message and recover, which a flag does
      not. A single hook with a setter returning the previous one, for
      chaining, was considered too, and set aside for the list: chaining
      by hand is easy for a library to get wrong.
    - **Still open.**
      - On the VAX, the details of the message file (item 17).
      - To check before building way 2: whether `llvm.returnaddress`'s
        constant argument passes through a `["C"]` declaration; where
        `dladdr` lives on each platform (glibc before 2.34, the BSDs);
        whether every `NEW` calls `Allocate` directly, or some go
        through a helper that would be named instead.

16. The collector thrashes at the heap ceiling (the user, 2026-11-20;
    found in podoc). Not yet decided or started.
    - **What was seen.** podoc (poc 0.15.0, `-OC`, atla) converting a
      45 MB file to JSON needs a little more than the default 1 GB
      heap limit. It ran for 6 min 15 s, nearly all of it user time,
      before a `NEW` found no memory and the program stopped
      (`-trap-heap-exhausted`: trap 11, "heap exhausted"). pandoc took
      34 s and 2.9 GiB for the same file. Earlier, at 12 MB, before
      podoc's own memory fixes, two of its writers did the same for
      2 to 4 minutes before ending in a NIL trap.
    - **Why, from `rtl/llvm/GarbageCollectedHeap.Mod`.** When
      `TakeBlock` finds nothing, `Allocate` runs a full `Collect`, then
      `GrowAfterCollection`. At the ceiling `AddChunk` refuses, and the
      collection frees only what has died since the last one. So
      collections come every few allocations, and each marks and sweeps
      the whole of nearly 1 GB of live data. The program creeps forward
      until one request finds nothing even after a collection.
    - **What is wanted.** Give up early, so the program stops at once
      with "heap exhausted" (or NIL), not minutes later. For example,
      when the heap cannot grow and a collection leaves less than some
      fraction of the block area free (a few percent), count it, and
      after a few such collections in a row answer 0. Some collectors do
      the same (HotSpot's "GC overhead limit exceeded": more than 98% of
      the time in collection while freeing less than 2% of the heap).
    - **To decide with the user.** The threshold and how many
      collections in a row; whether it is on by default (item 15
      removes `-trap-heap-exhausted`, which it might have gone with);
      whether a program can set it, as it can `SetHeapLimit` and
      `SetChunkSize`; the VAX's collector, which has the same
      structure.

17. A VMS message file for poc's traps (the user, 2026-11-20; from item
    15). Decided in outline; the open points below are not, and nothing
    is started. What follows was read in poc's VMS docs and recalled
    from the VMS message utility, not tried on VMS.
    - **The need.** On VMS a poc trap writes its message and `$EXIT`s
      with `%X10000000 + 8*c + 2`: facility 0 (`SYSTEM`), message
      number *c*, severity error, DCL's message suppressed (bit 28).
      Facility 0 is VMS's own, so `$GETMSG`, `Conditions.Message` and
      `HELP/MESSAGE` give a system message, or none, for *c*, not
      poc's; and a trap that signals (item 15's out-of-memory trap,
      `LIB$STOP`) has no message of poc's to print.
    - **The proposal.** A message source, `POCMSG.MSG`, gives every
      trap a message in a facility of poc's own, `POC`, with *c* kept
      as the message number:
      ```
              .TITLE      POCMSG  poc run-time traps
              .FACILITY   POC, <number> /PREFIX=POC$_
              .SEVERITY   ERROR
              .BASE       2
      INDEX   <index out of range>
      NOCASE  <no matching CASE label>
      NILREF  <NIL pointer dereference>
      ...
      HEAPEXH <heap exhausted: NEW cannot allocate the block>
      ...
      HOOKFULL <AddOutOfMemoryHook: the table of hooks is full>
              .END
      ```
      The names are placeholders; the texts are reference-guide.md's
      trap table's. The condition value is then: severity in bits 0-2
      (error, or fatal after `LIB$STOP`); *c* in bits 3-14; bit 15, the
      facility-specific bit, and bit 27, customer-defined, both set by
      `MESSAGE`; poc's facility number in bits 16-26; bit 28 set as now
      for a trap that `$EXIT`s, so DCL does not repeat poc's message.
    - **Where it is built.** poc's VMS runtime is always built on VMS:
      `@BUILD` runs `POCRTL_BUILD.COM`, which assembles the modules'
      `.MAR` and makes `POCRTL.OLB` and `POCRTL.EXE`
      (vax-vms-guide.md's table of the kit). It would run `MESSAGE` on
      `POCMSG.MSG` and put the object in both, cross-compiled programs
      (`-vax-objects`) included. The trap code refers to the message
      symbols (`POC$_HEAPEXH`), so `LINK` takes the module in by itself.
    - **What it gives.** Every trap's status has poc's message:
      `$GETMSG`, `Conditions.Message`, `SET MESSAGE`. Item 15's
      out-of-memory trap `LIB$STOP`s with `POC$_HEAPEXH`, and VMS prints
      "%POC-F-HEAPEXH, ..." and its traceback. Other traps could later
      signal too, for their tracebacks; not part of this item.
    - **What changes.** The statuses: a DCL procedure's
      `($STATUS .AND. %XFFF8) / 8` (reference-guide.md) gives *c* + 4096
      with bit 15 set, and becomes `.AND. %X7FF8`; reference-guide.md,
      vax-vms-guide.md and the VAX tests that check statuses change with
      it. A release-note item.
    - **To decide with the user.**
      - The facility number. Customer facilities are not registered, so
        a clash with other local software is possible, if unlikely.
      - `HALT(c)`, which shares the traps' encoding today (so `HALT(4)`
        looks like a NIL trap): stay in facility 0, or move to `POC`
        with numbers that have no message.
      - `-trap-location`'s per-site text, which a fixed message cannot
        hold: poc keeps writing its own line first, or the message
        takes an `!AS` argument when signalled.
      - The messages' names.
    - **To check on VMS.** That `$PUTMSG` and the last-chance handler
      find a message section linked into the shareable `POCRTL.EXE`, and
      into a program linked with `POCRTL.OLB`; that `MESSAGE` sets bits
      15 and 27 as above; that `.BASE` gives the numbers wanted.

## Open design questions

None at present.

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
- The lowest 32-bit x86 CPU (decided 2026-11-18:
  `doc/developer/32-bit-x86-cpu.md`)

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
