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

Those done while Phase 17 was current, 3, are in
`doc/history/phases/phase-17.md`.

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
      VMS, linked into the program or put in the library: next, designed
      (2026-10-27) in seven proposals, 1-4 and 7 in
      `doc/developer/llvm-toolchain.md`, "Object files on the command
      line", 5 and 6, the VAX's, in `doc/developer/vax-macro32-backend.md`,
      section 13.1. The guest showed (2026-10-27) that a VMS object
      fetched by FTP in binary loses its record boundaries, so on Unix
      poc takes only a counted-form object and refuses others; and a
      VAX library reads an object's global symbols to make them
      universal (the user, 2026-10-27). LLVM first, then the VAX. The
      LLVM side, 1-4 and 7, is done (2026-10-27; fixture
      `poc-object-files`); the VAX's, 5 and 6, next.

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
