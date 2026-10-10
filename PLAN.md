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
VAX/VMS 5.5-2 (a SIMH-hosted VAX, or real hardware), with just enough
runtime to compile poc itself, and poc - built for VAX/VMS - then compiles
its own source *on* VAX/VMS: the VMS counterpart of Phase 10's
self-hosting. This lifts two limits of earlier phases, which no longer
apply once it starts: the locked-in "linking/running is out of
scope" (Phase 15 stays what it was - hand-reviewed and non-executable -
and this phase is what runs it), and Phase 15's own scope bound to Phase
8's vertical slice, since poc's source uses far more than that.

**Explicit non-goals**: libraries beyond what poc's own source needs
(Phase 17); any VMS other than VAX 5.5-2 - no Alpha, Itanium, or later VAX
release, though nothing should be gratuitously specific to the exact
release; DECnet, DECwindows, layered products. Phase 17 owns shareable
images and the native VMS libraries; this phase links objects and, at
most, object libraries.

1. **A working VAX/VMS environment and a way to drive it.** Partly
   brought forward into Phase 15 (2026-10-05): the development system is a
   SIMH `microvax3900` running VMS 5.5-2H4, and Phase 15 copies `.mar`
   files to it to assemble them. Settle what runs: which SIMH VAX model VMS 5.5-2 boots on, and where the installation
   media and licences come from.
   Confirm on the guest what the base kit provides (`MACRO`, `LINK`,
   `LIBRARY`, `DCL`, the RTLs) and which layered tools poc must not depend
   on. Decide how files cross between the Linux/BSD host and the guest -
   virtual disk image, tape image, `kermit`, `ftp`, a shared mount - and
   how a test is driven and its output captured (a serial or telnet
   console script). Automate that as one host-side command that copies
   sources in, runs a `.COM` procedure, and copies results out, since
   every later step's fixtures depend on it. Recorded in the plan, with
   the choices that were rejected.

   **Record** (2026-10-09):
   - *The system.* SIMH's `microvax3900` (`VAXserver 3900 Series`, a
     KA655) runs VMS `V5.5-2H4`, the later hardware release of 5.5-2,
     on `DUA0:` (system) and `DUA1:` (users, `POC`'s
     `DUA1:[USERS.POC]`), at `192.168.2.20` while SIMH runs on atla.
     It had 64 MB, the KA655's most; the user gave SIMH 256 MB
     (2026-10-09), which VMS uses (`SHOW MEMORY/PHYSICAL`: 524288
     pages). The licences are hobbyist PAKs (`OPENVMS-HOBBYIST`,
     `VAX-VMS`); the user decided they need no further record.
   - *The base kit*, confirmed with `tools/vax-do` (below): `MACRO32`,
     `LINK`, `LIBRARIAN`, `DCL`, the debugger (`DEBUG.EXE`,
     `DEBUGSHR.EXE`), `DIFF`, `SEARCH`, `SORTMERGE`, `BACKUP`, `CONVERT`,
     `ANALYZE/OBJECT` and `/RMS`; in `SYS$LIBRARY` `LIBRTL`, `LIBRTL2`,
     `MTHRTL`, `STARLET.OLB`, `.MLB` and `STARLETSD.TLB`, `LIB.MLB`,
     `IMAGELIB.OLB`. Layered products installed: VAX C 3.2
     (`VAXCRTL`), FORTRAN 5.6, BASIC 3.4, Ada 3.0, MMS 2.6 and UCX 3.1;
     MMK's release notes are there but no `MMK.EXE` in `SYS$SYSTEM`.
     **Decided (the user, 2026-10-09): poc depends on none of the
     layered products** - the guest-side build driver is a `.COM`
     procedure, not MMS (step 5), and the runtime uses only `LIBRTL`,
     `MTHRTL` and system services, not `VAXCRTL` - so that poc runs on a
     VAX with the base kit alone.
   - *Files cross by FTP* (UCX 3.1; active mode, ASCII for text), *and a
     command runs by telnet*, as Phase 15 settled (`doc/developer/
     vax-macro32-backend.md` §11, question 2). Rejected: a virtual disk
     or tape image (SIMH must stop to change it), Kermit (none on the
     guest), a shared mount (NFS needs UCX's server set up, a change to
     the system), `rsh` (`UCX$RSH.EXE` is there, but UCX lists only FTP
     and TELNET as services and ports 512-514 are closed), and a batch
     job watching a directory (kept in reserve).
   - *The host-side command*: `tools/vax-do [-o <dir>] [-get
     <NAME.EXT>]... <proc.com> [<file>...]` copies the procedure and its
     files in, runs `@<PROC>/OUTPUT=VAXDO.LOG`, and copies the log and
     the files named back, deleting its copies on the guest; it holds the
     guest's lock, as `tools/vax-assemble` and `tools/vax-run` do (2-3 s
     a run, most of it FTP and telnet logins). Its output comes back as
     files, never read from a terminal, which a long listing overflows.
   - *Memory*: poc compiling its own source in one process peaks at
     92 MB on x86-64 and 105 MB on 32-bit OpenBSD
     (75 MB of it data), and `POC` may have 10240 pages of paging file
     (5 MB), a working set of 1024 to 2048 pages (0.5 to 1 MB), and a
     process at most `VIRTUALPAGECNT` 139072 pages (68 MB), on what was
     a 64 MB machine. Step 6 cannot run under these. Choices: raise `POC`'s
     `PGFLQUOTA`, `WSQUOTA` and `WSEXTENT` (`AUTHORIZE`) and the system's
     `VIRTUALPAGECNT` (`SYSGEN`) and page file, all privileged changes to
     the guest; give SIMH more memory (SIMH documents an extended
     KA655X with up to 512 MB; whether VMS 5.5-2 uses it is to be
     checked); and make poc need less. **Decided (the user,
     2026-10-09): poc needs less**; the guest is not changed. The user
     then gave SIMH 256 MB (above) and kept the decision: `POC`'s quotas
     and `VIRTUALPAGECNT` stay as they are. One module
     at a time is not enough by itself: compiled alone with `-compile`
     (its imports' `.sym` files made, clang replaced by a stand-in so
     only poc is measured), on 32-bit OpenBSD, `LLVMCodeGenerator` peaks
     at 82 MB, `VaxCodeGenerator` at 59 MB, `SemanticActions` at 45 MB,
     `Lexer` at 13 MB. The collector grows the heap to twice the live
     data after a collection (`GarbageCollectedHeap`, "Heap shape"), so
     the live data is about half of that: what holds it - the syntax
     trees, the symbol tables, the code being written - and how much a
     module's compilation can drop is step 4's and step 6's to find.
     `POC`'s 5 MB of page file is an order of magnitude below the
     largest module's 40 MB or so of live data, so this decision is to
     be revisited if that cannot be closed.

2. **Assemble, link and run hand-written, then generated, code.** Before
   any generated code: a hand-written MACRO-32 "hello" through
   `MACRO`, `LINK` and `RUN`, proving the loop end to end. Then every
   `expected-vax.mar` fixture Phase 15 checked in is assembled and run,
   turning "hand-reviewed" into automated pass/fail wherever the fixture
   is runnable; whatever the assembler rejects is a Phase 15 bug and is
   fixed there. `VaxToolchainDriver.Mod` stops being a stub: it emits the
   `.mar`, drives `MACRO`/`LINK` (locally on the guest, or by the step 1
   command from the host).

   **Record** (2026-10-09):
   - *The hand-written program*, `test/conformance/vax-hello/
     hand-hello.mar`, calls `LIB$PUT_OUTPUT` and is assembled, linked and
     run on the guest by the fixture's `guest-hello.com`, through
     `tools/vax-do`. Its line and `$STATUS` are compared
     (`test/vaxfixture.sh`, `vax_do`).
   - *The Phase 15 fixtures* were already assembled and run before this
     step: all 32 `expected-vax.mar` assemble clean, and the 28 fixtures
     with code to run do so under the debugger, their logs compared
     (`tools/vax-run`). The assembler rejected nothing, so step 2 found no
     Phase 15 bug to fix. A plain `RUN` of each would show only an exit
     status until the runtime has `Out`, so none was added.
   - *The driver*. **Decided (the user, 2026-10-09): on the host, poc
     writes the `.mar` files and a DCL build procedure and runs nothing on
     VMS.** `-target vax-dec-vms -build` writes `<name>.com`, which
     assembles the modules and links `<NAME>.EXE` through an options file
     with poc's runtime, `POCRTL.OBJ` (`rtl/vax/PocRtl.mar`; from
     `POC$RTL:` when that is defined). `-compile` writes `<First>.com`,
     which only assembles. A warning, such as `%LINK-W-MULDEF`, stops
     either. `-library` and `-install-library` stay refused (Phase 17).
     The same procedure serves poc on VMS later (step 6).
     `doc/developer/vax-macro32-backend.md` section 13.
   - *The runtime's first cut*: `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and
     `POC_HMOD` as the debugger stub has them. `POC_TRAP` and `POC_HALT`
     are provisional (they exit with `SS$_ABORT` and `SS$_NORMAL`) until
     step 3c.
   - *Section 5.1's layer 2*, for the modules poc writes in one run: their
     exported symbols share one table, so a collision between two modules
     is an error at the second declaration, in its own file. So are two
     modules whose names differ only in case. Errors found while a module
     is written now name that module's file, not the main module's.
   - *Fixture* `vax-build`: a two-module program built with `-build` and
     `-compile`, its procedures compared with `expected-<name>.com`, then
     run on the guest. Its exit status, `%X00003735`, encodes what it
     computed (a loop, a `HUGEINT` product and quotient, a string
     comparison, an imported variable). Also `-o`, and the refusals: a
     name that is not a VMS image name, `-OC`, the clash, and the case
     collision.

3. **Widening the backend to what poc's own source uses.** Survey poc's own
   source (`src/`) for every construct it needs - pointers and `NEW`,
   records and extension, type-bound procedures, `WITH`/`IS`, open arrays,
   sets, `REAL`/`LONGREAL`, procedure values and procedure-typed
   parameters, strings and `CHAR` arrays, `CASE`, external procedures - and
   bring `VaxCodeGenerator.Mod` to parity with the LLVM backend for those,
   in dependency order, and `SYSTEM.SET64` whether poc's source uses it or
   not (the user, 2026-10-08; only the runtime's `Texts` does, and Phase 15
   left it out of the slice), each with a run-and-diff fixture that is also
   a Phase 9 fixture (the same `.mod`, same expected output, on both
   backends; a fixture that only one passes is a bug). Three things need
   real design, not just porting: (a) **floating point** - VAX
   `REAL`/`LONGREAL` are F_floating and D_floating (or G), not IEEE 754, so
   constant emission, `ConstantEvaluator`'s folding, `MAX`/`MIN` of the
   real types, `ParseReal`/`FormatReal` and the `.sym` round trip, and the
   hardware conversions all change; decide the `LONGREAL` format (D or G)
   from what VMS's own compilers and RTLs default to; (b) **calling
   convention** - internal Oberon procedures versus the VMS Calling
   Standard (`CALLS`/`CALLG`, argument lists, register save masks,
   condition values); Phase 15 says external procedures use the standard
   and ordinary ones poc's own, and this step decides whether the hidden
   tag/length arguments and procedure values keep working that way or
   whether one convention for everything is simpler (Phase 17's AST support
   pulls toward the latter); (c) **traps** - index, NIL, type-guard and
   length failures become VMS conditions or a status exit, and what a poc
   program's exit status looks like to DCL.

   **Record** (closed by the user 2026-10-10: poc's own source is written
   with no refusal):
   - **Decided (the user, 2026-10-09): the VAX takes `-OC` as well as
     `-O2`.** poc's own source needs `-OC` (a 64-bit `LONGINT`) and must
     stay strict, so it can't use `HUGEINT`. Under `-OC` a `LONGINT` is a
     quadword, lowered as a `HUGEINT` is; `-O2` stays the default
     (`VaxTypes.sizeModel`, `VaxTypes.Longword`). The 32 reviewed `.mar`
     files are unchanged. Fixture `vax-size-model-oc` (its
     `expected-vax.mar` reviewed by the user) runs on the guest with
     every check holding.
   - *The survey*: under `-OC`, poc's own source has 22,504 constructs
     the backend refuses, most of them pointers (13,606), records holding
     pointers or passed as `VAR` (4,506) and open arrays (4,340). The
     proposals for each area, for reals (3a), the calling convention (3b)
     and traps (3c), and the order of work are in
     `doc/developer/vax-macro32-backend.md` section 14. **Approved by the
     user, 2026-10-09**, as is `vax-size-model-oc`'s `expected-vax.mar`.
   - Found on the way: Phase 15 had broken the rule that poc's own source
     type-checks under `-O2` (`AGENTS.md`), with five constants past
     `MAX(LONGINT)` in `VaxCodeGenerator`; fixed, and `poc -O2
     -emit-llvm-ir src/driver/Poc.Mod` is clean again. Nothing checks the
     rule automatically.
   - *Open arrays* (section 14 item 1), done 2026-10-09: parameters by
     value and `VAR` with any number of open dimensions, `LEN`, indexing
     with trap 2, `COPY`, comparisons, and assignment to a fixed array
     with trap 9. Fixture `vax-open-arrays` has debugger runs of both traps
     and guest runs under `-O2` and `-OC`; its `expected-vax.mar` was
     reviewed by the user (2026-10-09). Every reviewed `.mar` file is unchanged.
     Survey: 19,443 refusals left, none of them an open array.
   - *A minimal `Out`* (section 14 item 2), done 2026-10-09:
     `rtl/vax/Out.Mod` (`Open`, `Flush`, `Char`, `String`, `Ln`, `Int`,
     `Hex`) over `POC_PUT_LINE` (`LIB$PUT_OUTPUT`), with an exit handler
     for a line left without `Ln`. Fixture `vax-out` runs one source on
     both backends, under `-O2` and `-OC`, against one expected output per
     model. Its `.mar` files were reviewed by the user (2026-10-09). This found the
     voc-built poc's wrong high longword for `MIN(HUGEINT)` (vishap-bugs
     07), now fixed.
   - *Pointers, `NEW` and type descriptors without extension* (section 14
     items 3 and 4), done 2026-10-09: NIL-checked dereference (trap 4),
     `NEW` through `POC_NEW` over `LIB$GET_VM` (an open array's lengths
     checked, trap 7), and LLVM's descriptor layout, every module-level
     record's descriptor global. Fixture `vax-pointers` runs on the
     debugger and, printing with `Out`, on both backends under `-O2` and
     `-OC`. Its `.mar` files, and the three earlier ones that gained
     descriptors (`vax-declarations-only`, `vax-records`, `vax-modules`'
     `VaxModLib`), were reviewed by the user (2026-10-09). Survey: 10,859
     refusals left, most of them extension and the records holding its
     pointers.
   - *Records holding pointers and `VAR` record parameters* (section 14
     item 5), done 2026-10-09: a `VAR` record parameter of an Oberon
     procedure takes its actual's type tag after its address, as on
     LLVM. Fixture `vax-var-records` examines the tags received under the
     debugger and runs one source on both backends. Its `.mar` files, and
     `vax-records`' and `vax-modules`' two, which pass the tag now, were
     reviewed by the user (2026-10-09). Survey: 10,889, unchanged outside
     `VaxCodeGenerator.Mod`, whose new code adds 30.
   - *Extension, `IS`, type guards and `WITH`* (section 14 item 11's next
     step), done 2026-10-09: descriptors with their extension level and
     base types, LLVM's type test, guards (trap 5), `WITH` (trap 6) and
     the record-assignment check (trap 13). Fixture `vax-extension` takes
     each trap under the debugger and runs one source on both backends.
     Its `.mar` files were reviewed by the user (2026-10-09). Survey: 388,
     none of them extension.
   - *Type-bound procedures* (section 14 item 6), done 2026-10-09: each
     record's `ProcTab` below its tag, as on LLVM, and calls through it
     or, when the receiver's type is known exactly or for `v.P^`,
     directly. Fixture `vax-type-bound` takes traps 4 and 5 from receivers
     under the debugger and runs one source on both backends. Its `.mar`
     files were reviewed by the user (2026-10-09). Survey: 388, unchanged,
     poc's source having no type-bound procedures.
   - *Procedure values* (section 14 item 7), done 2026-10-09: a procedure
     value is the longword address of a procedure's entry mask, NIL 0,
     compared as a longword, and a call through one checks it for NIL
     (trap 4) before its arguments, then `CALLG list, (Rn)`. Fixture
     `vax-procedure-values` takes trap 4 from a variable and an element
     under the debugger and runs one source on both backends. Its `.mar`
     files were reviewed by the user (2026-10-09). Survey: 270, none of
     them procedure values.
   - *Nested procedures* (section 14 item 8), done 2026-10-09: lambda
     lifting by reference, as on LLVM - each nested procedure a procedure
     of its own, taking the addresses of the enclosing procedures'
     variables it needs (`NestedProcedures.Analyze`) after its own
     parameters. Fixture `vax-nested` takes traps 4 and 2 in nested
     procedures under the debugger and runs one source on both backends.
     Its `.mar` file was reviewed by the user (2026-10-09). Survey: 263,
     none of them nested procedures.
   - *Reals* (section 14 item 9), done 2026-10-09: `REAL` is F_floating,
     `LONGREAL` G_floating; a constant is decimal text MACRO converts,
     rounding as the VAX does (halfway away from zero); `ENTIER` floors
     and traps (8) past `LONGINT`'s range, with `POC_ENTIERQ` under
     `-OC`, and a `HUGEINT` converts by `POC_QTOG`. Fixture `vax-reals`
     examines the rounding, trap 8 and the divide-by-zero fault under
     the debugger and runs one source on both backends. Its `.mar` file
     was reviewed by the user (2026-10-09). Survey: 78, all `SYSTEM.BYTE`
     parameters.
   - *Traps and `HALT`* (section 14 item 10), done 2026-10-09:
     `PocRtl.mar`'s `POC_TRAP` writes LLVM's message to `SYS$ERROR` and
     exits with `%X10000000 + 8*c + 2`; `POC_HALT` exits with
     `SS$_NORMAL` for 0, else the same; `-trap-location` adds the file
     and the procedure to the call. Fixture `vax-traps` runs one program
     on both backends for each trap and `HALT`, and compares messages and
     statuses. Its `.mar` file, and `vax-range-checks`' again (`CHR`'s
     code), were reviewed by the user (2026-10-09).
   - *`ASSERT`* (section 14 item 11), done 2026-10-09: a branch on the
     condition to trap 10 at the statement, `ASSERT(x, n)`'s *n* + 1 in
     the code's high word for "assertion failed (n)". Fixture `vax-assert`
     runs one program on both backends for each case. Its `.mar` file
     was reviewed by the user (2026-10-09). Survey: 78, unchanged.
   - *`SYSTEM.SET64`* (section 14 item 11), done 2026-10-09: a quadword
     lowered as a `HUGEINT`, each operation on both longwords; `IN` of a
     register pair by `ASHQ` and `BLBC`, `BBC` taking only bits 0..31 of
     a register. Fixture `vax-set64` runs one program on both backends.
     Its `.mar` file was reviewed by the user (2026-10-10). Survey: 78,
     unchanged.
   - *`SYSTEM.BYTE` parameters*, done 2026-10-10: `BYTE` a byte in the
     slice; a `VAR ARRAY OF SYSTEM.BYTE` takes any variable, its length
     the variable's size in bytes. Fixture `vax-byte-params` runs one
     program on both backends. Its `.mar` file was reviewed by the user
     (2026-10-10). Survey: none in poc's own source; the 179 left are
     `rtl/llvm`'s, which step 4 replaces.
   - *Closed* (the user, 2026-10-10). Step 3 ended as section 14 item 11
     said it would: poc's own source is written for the VAX with no
     refusal. Every construct it uses is lowered, each with a fixture run
     on both backends, and every `expected-vax.mar` was reviewed by the
     user.

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
   decide, and say which) Decided (2026-10-05): poc on VMS matches its options
   without regard to case, so `-BUILD` is `-build`; their names stay
   lowercase (`doc/developer/vax-macro32-backend.md` §10). Module and file
   names given as arguments are still this step's question.

   **Record** (in progress, 2026-10-10):
   - *The survey and proposals* are in
     `doc/developer/vax-macro32-backend.md` section 15. **Approved by the
     user, 2026-10-10.** poc's source imports `Files`, `Platform`, `Out`,
     `Err` and `Modules`. Checked on the guest: what a foreign command's
     line looks like (`LIB$GET_FOREIGN`), and that `MACRO` and `LINK`
     read Stream_LF files.
   - *`Modules`, `Platform` and `Err`* (2026-10-10) are in `rtl/vax`,
     with the fixtures `vax-command-line`, `vax-platform` and `vax-err`.
     Their `expected-vax.mar` files were reviewed by the user
     (2026-10-10), as were `vax-out`'s, since `Out` now writes through
     `LineOutput`, which it shares with `Err`. Checked on the guest:
     `Unlink` deletes only the highest version.
   - *`Directories`* (2026-10-10; proposal 4, amended with the user):
     `pathSeparator`, `MakePath`, `IsDirectory` and `MakeDirectory`,
     first added to `Platform`, are a module of their own in `rtl/vax`,
     `rtl/llvm` and, for the Stage 0 poc, `rtl/voc`, so that `Platform`
     keeps voc's interface. `src/` names its files and directories
     through it. `vax-platform`'s `expected-vax*.mar` files, redrafted,
     were reviewed by the user (2026-10-10).
   - *The module name check and the default target* (2026-10-10): a VAX
     module's name over 26 characters (which keeps its files within
     ODS-2's 39) is refused before its `.sym` is written; a poc built
     with `tools/build-info <dir> vax-dec-vms` compiles for the VAX by
     default and has no other target.

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

7. **Exit gate.** Every module and interface chosen builds into both
   library kinds and passes its fixtures on the guest, the AST fixtures
   pass repeatedly (asynchrony makes a single pass weak evidence), and the
   whole VAX conformance suite from Phase 16 is still clean.

**Testing summary**: steps 1, 3, 5 and 6 are fixtures run on the guest;
steps 2 and 4 are decisions with written artifacts, verified against the
manuals they cite; step 7 is the gate.

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
   type, under that name only (the user). Not built yet.

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
