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
backend (Phase 15) because the library question is an LLVM/Unix one and
nothing in the VAX work depends on it.

**Done** (closed 2026-10-02). The full account - design, every step, what
was found and decided along the way, testing - is in `doc/phases/phase-12.md`,
under the same step numbers:

- **1.** Which of voc's command-line options poc needs (`doc/voc-options.md`).
- **2.** Building static and dynamic libraries with poc: 2a per-module code
  generation, 2b module keys, 2c `-library`, 2d `poc-rtl` built by `make`,
  2e using modules and libraries, 2f compiled modules without source
  (`-compile`), 2g `-lto`, 2h the fixtures.
- **3.** A complete inventory of the libraries and modules voc supplies
  (`doc/voc-module-inventory.md`).
- **4.** Deciding what poc supports: voc's runtime modules; its `src/library`
  waits for Phase 20.
- **5.** Implementing the runtime modules: 5a `Platform`, 5b `In.Name` and
  `VT100`, 5c finalization, 5d `Files`, 5e `Modules`, 5f `Reals`, 5g
  `Texts`, 5h `Oberon`.
- **6.** Exit gate.

### Phase 13 — Packaging, installation, and the User's and Reference Guides

**Inserted 2026-10-02 (user)**, before the VAX/VMS work: the phases after it
were renumbered, so the old Phases 13-18 are now 14-19. Records of closed
phases (`doc/phases/`, `doc/phase-11-inventory.md`, `doc/project-history.md`,
`doc/initializers-and-literals-survey.md`) keep the numbers they were
written with: there, "Phase 13" is today's Phase 14, and so on up to "Phase
18", today's 19. A second renumbering followed the same day, when record
and array literals became Phase 14 (user, 2026-10-02): the Phases 14-19
of that first renumbering are now 15-20, so a record written between the
two (`doc/phases/phase-12.md`) means today's 15-20 by its 14-19.

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

**Decided with the user (2026-10-02)**: a new phase, not a Phase 12 step;
the guides in Markdown under `doc/` (installed to the documentation
directory) plus a `poc(1)` page in mdoc, which Linux's and the BSDs' `man`
all render; and all four of `make install`, a bootstrap seed, a release
tarball and OS packages.

**Explicit non-goals**: packaging for VAX/VMS (a VMS kit belongs with the
VAX phases); Windows and macOS; a stable binary interface between poc
releases (a library built by one poc version is not promised to link with
another's programs; the module keys of Phase 12 step 2b already refuse a
mismatch).

1. **Version and identity.** A version number for poc, kept in one place
   in the source; `poc -version` prints it with the default target triple
   and size model (and the clang it found). Decide with the user: the
   scheme (e.g. 0.x until the first release meant for others), and
   whether a build from a git checkout adds the commit. Every `.sym`,
   library manifest and object could record the poc version that wrote it;
   decide whether a mismatch is refused, warned about or ignored.
   **Done (2026-10-02).** Decided with the user: 0.x.y, starting at 0.1.0,
   until a release meant for others; a build from a git checkout adds its
   commit; only a library's manifest records the version, and a library
   another version wrote is refused. `src/driver/Version.Mod` holds the
   number. `tools/build-info` writes `build/gen/BuildInfo.Mod`, the commit
   (`-dirty` when tracked files differ, empty with no `.git`), rewriting it
   only when that changes; `make` runs it every time, so a new commit
   rebuilds poc, and each bootstrap stage runs it too, so a stage still
   works alone. `poc -version` (after any `-target`, `-O2`, `-OC`) prints
   `poc 0.1.0 (<commit>)`, the target and size model, and the first line of
   `clang --version` (or that there is none). The manifest's new line is
   `poc <number>`: the number only, not the commit, since every commit
   would otherwise make a developer's libraries unusable, and module keys
   already refuse a changed interface. A library without the line, or
   with another number, is refused with "rebuild it", once per library
   (`Libraries.Load` now remembers a refused manifest, which was said once
   per lookup before, for a wrong triple too), and the note on the import
   it leaves missing points to that. `.sym` files and objects are
   unchanged. Fixture `poc-version`; `poc-usage` has the new usage line,
   and `llvm-libraries` and `llvm-using-modules` mask the manifest's
   version.
2. **What a user has to work with: a walk-through.** Before any code,
   use poc as a newcomer would, from the outside: a one-module program, a
   program of several modules in several directories, a library of the
   user's own (static and shared), a program using it from another
   directory, `-g` and a debugger, a voc program ported to poc, a module
   with a C part. List every rough edge found (where poc writes its
   `.sym`/`.ll`/`.o` files, what an error message assumes, what needs an
   environment variable, what only works from the source tree), and
   decide each with the user: fix in this phase, document, or leave.
   **Done (2026-10-02).** Walked through with only an installed-like
   prefix and the system on `PATH` (no voc, no source tree): one module;
   modules in several directories; a library of one's own, static and
   shared, used from another directory; `-g` with gdb; voc's own test
   programs (`testFiles`, `argTexts`, `md5test`, Lola); a module with a C
   part; a trap. Decided with the user:
   - **Fix in this phase.** `poc <file>` means `-build`, and the
     executable is named after the module unless `-o` says otherwise
     (until now `poc Hello.Mod` printed the usage, and `-build` required
     `-o`). `-build`, `-library` and `-compile` are silent on success
     (`-check` keeps "semantic OK", its answer). `-help`/`--help`/`-h`
     print a short summary on standard output and exit 0, pointing to
     `poc(1)` (they printed the whole usage as an error); and compile
     errors name what is wrong ("undeclared identifier" names it; a type
     mismatch names the types where that is cheap), after an audit of
     every message. `-c-flag <arg>`, repeatable like `-link`, passes
     `<arg>` to clang for a module's `.c` part (`-I`, `-D`). A false "a
     record may not directly contain itself", which stops voc's Lola test
     (`LSB.Mod`; a record's extension reached through pointers while its
     base is still being resolved), fixed first, in a commit of its own.
     *Done (2026-10-02).* `poc <file>`, the executable's default name,
     the silence (93 fixtures' expected outputs lost the line, and 12 that
     dropped it with `tail -n +2` before comparing with voc now take the
     whole output), `-help` (`Poc.Help`), `-c-flag`
     (`LLVMToolchainDriver.AddCFlag`; fixture `poc-c-flag`); the Lola fix
     is `3dc49ce`, with the rule of 6.3 that an extension's fields differ
     from its bases', which poc had never checked. The audit: an error
     about a name now says it, "message: details" (`Diagnostics.
     ErrorAbout`): an undeclared, unexported or redeclared identifier,
     field or module, qualified as written (`undeclared identifier:
     Out.Strng`); a mismatched `END` (`END R, not END Q`). One about types
     names them (`Types.Describe`: a basic type by name, a record by its
     name, `M.R` from another module, the rest by structure, `POINTER TO
     Node`, `ARRAY 4 OF CHAR`): an assignment or `VAR` argument
     (`assignment is not type-compatible: CHAR to INTEGER`), an operator's
     operands (`BOOLEAN and SET`), a call of something not a procedure,
     and a predeclared procedure's wrong argument (`ODD requires an
     integer argument: REAL`). Messages that already say all there is
     (`a VAR parameter requires a variable argument`) are unchanged.
     Fixture `semantic-error-details`; 43 others' expected outputs gained
     only the details.
   - **Step 3.** poc-rtl installed twice per size model: as now, and a
     copy built with `-g` that `poc -g` links, so a debugger sees into the
     runtime while ordinary programs stay small (measured: `-g` leaves the
     code and its speed unchanged, but makes a statically linked program
     about 4 times larger on disk, 31 KB to 125 KB). A shared executable's
     run-time path names each library directory both relative to
     `$ORIGIN` and absolutely; settle what an installed one should have.
   - **Document** (the User's Guide): a build writes each module's
     `.sym`, `.ll` and `.o` in the current directory, as voc does
     (`-output-dir` moves them); the import path is not searched
     recursively; every module is compiled again on each build; `poc
     -library` without `-output-dir` writes `./<triple>/<O2|OC>/`, which
     `-library-path .` finds; a trap names its location only with
     `-trap-location`.
   - **Leave**: voc's library modules (`md5test`'s `ethMD5`) wait for
     Phase 20.
3. **The installed layout and `make install`.** `make install` and `make
   uninstall` with `PREFIX` (default `/usr/local`), `DESTDIR`, and the
   usual `BINDIR`, `LIBDIR`, `MANDIR`, `DOCDIR`, on GNU make (`gmake` on
   the BSDs). It installs the Stage 2 poc (built by poc, so needing no
   `libvoc`), `poc-rtl` for the host triple under both size models, static
   and shared, where poc's default library path already looks
   (`<bindir>/../lib/poc/<triple>/<O2|OC>/`), `poc(1)` and the guides.
   Check against each OS's conventions (`hier(7)`; FreeBSD and OpenBSD
   ports install under `/usr/local`, pkgsrc under `/usr/pkg`), what a
   shared `poc-rtl`'s run-time search path is once installed, and that a
   poc reached through a symbolic link still finds its library. A `make
   check-install` target installs into a scratch `DESTDIR` and runs a set
   of fixtures with only the installed poc: no voc on `PATH`, no source
   tree, no `POC_IMPORT_PATH`.
   **Done (2026-10-02).** Decided with the user: the `-g` copy of a
   library lives beside the plain one, in `<triple>/<O2|OC>-g/`; under
   `poc -g` every base on the library path is searched there first, then
   as usual, and `poc -g -library` (and `-install-library`) writes there,
   so a user's own libraries can have a debug copy too
   (`Libraries.SetDebug`; both copies have the same keys). A library in
   poc's own `../lib/poc` is "installed", and a program linking its shared
   library has it in its run-time path only absolutely
   (`Libraries.IsInstalled`, `LLVMToolchainDriver.AddLibrary`); others keep
   the `$ORIGIN`-relative entry first. Found on the way: a poc reached
   through a symbolic link looked for `../lib/poc` beside the link;
   `Libraries.PocLibraryDir` now follows links (with `readlink`, without
   `-f`). `make install` installs `build/stage2/bin/poc` (a file target
   now, made when missing or older than Stage 1), poc-rtl built by it in
   `build/stage2/lib/poc` under `O2`, `OC`, `O2-g` and `OC-g`, copied by
   `poc -install-library`, and `README.md` and `LICENSE` in `DOCDIR`
   (`share/doc/peaseblossom`); `MANDIR` is `share/man`, or `man` on
   OpenBSD and NetBSD, for `poc(1)` in step 7. An installed poc-rtl is
   0.66 MB a size model, 1.4 MB its `-g` copy. `make uninstall` removes
   poc-rtl's files by its manifests, so other installed libraries stay.
   `make check-install` installs into a `mktemp` `DESTDIR`, runs
   `test/install/check.sh` (a program under `-O2` and `-OC`, `-g` linking
   `O2-g`, a shared link run after moving the executable, a library of
   one's own used from another directory, static and shared, poc through a
   symbolic link, a trap, `-help`) with `PATH` only poc's, clang's,
   `/usr/bin` and `/bin`, then uninstalls and checks no file is left.
4. **The bootstrap seed: building poc without voc.** voc ships generated
   C so that it can be built with a C compiler alone; poc can ship the
   `.ll` it generates for itself (Stage 2's output, under `-OC`, which
   poc's own build uses), so that clang alone builds it. A `.ll` names a
   target (datalayout and triple), so a seed is per target: decide with
   the user which (x86_64 Linux and the three BSDs, i386 OpenBSD and
   NetBSD, aarch64 FreeBSD; or one per architecture, its triple
   substituted at build time, if the IR is otherwise the same - to be
   checked), and whether the seed is kept in git or only in the release
   tarball (a seed is several megabytes; regenerating it on every commit
   to the compiler would bloat the history). `make` then builds from the
   seed when voc is absent, and a `make seed` target regenerates it; a
   fixture checks that a seed-built poc reaches the same fixed point as a
   voc-built one. `poc-rtl` is built by the seed-built poc, as by any
   other.
   **Done (2026-10-02).** Checked first: poc's IR for itself depends only
   on the word size. Every 64-bit target's (x86_64 Linux and the three
   BSDs, aarch64 FreeBSD) differs from the others only in its `target
   triple` lines and `<M>.-target.<triple>` symbols, and so does each
   32-bit x86 BSD's; i686 Linux's also lacks the BSDs' stack realignment.
   (On the way: aarch64 got x86_64's `target datalayout`, poc having had
   one string per word size. clang takes the target's own over a module's,
   so no build showed it; fixed after the step's commit:
   `LLVMTypes.DataLayout` has x86_64's, 32-bit x86's and aarch64's (FreeBSD
   clang 19's), and no line for an architecture poc has not been run on;
   `stage0-seed` drops the seed's line; fixture `llvm-datalayout`.) Decided
   with the user: two seeds by word size, and the seed only in the release
   tarball, never in git. `make seed` (`tools/bootstrap/make-seed`) has
   the Stage 2 poc write `seed/64` (for `x86_64-unknown-linux-gnu`) and
   `seed/32` (`i386-unknown-openbsd`) under `-OC`, 30 modules each, 6.7
   MB (1.0 MB gzipped), with `TRIPLE` and `VERSION`, and checks that the
   triple is in each module only twice. `tools/bootstrap/stage0-seed`
   replaces it with `clang -dumpmachine`'s, compiles each module as poc
   would (`-fPIC`, `-O2`, or `-O0` for 32-bit x86) with
   `rtl/llvm/Platform.c`, and links `build/bin/poc`; another word size, or
   a 32-bit x86 other than OpenBSD's and NetBSD's, is refused.
   `tools/bootstrap/stage0` now chooses: `BOOTSTRAP_POC`, a poc already
   built (an installed one), compiles poc (`stage0-poc`), which lets a
   developer drop voc too; else the seed, if there is one; else voc; else
   it says which three it lacks. (Step 5 moved `make seed`'s output to
   `build/seed`, so that a top-level `seed/` is only a tarball's, and put
   the seed before voc, so a tarball always builds from its own.) `make check-seed` builds a Stage 0 from
   the seed and a Stage 1 with it in `build/seedcheck`, and compares that
   Stage 1's output with the voc-built Stage 1's: identical.
5. **The release tarball.** `make dist` writes
   `peaseblossom-<version>.tar.gz`: the source, the seed, the generated
   documentation, `LICENSE` and the README, but no test outputs or build
   products. `make distcheck` unpacks it in a scratch directory, builds
   it without voc, installs it into a scratch `DESTDIR` and runs `make
   check-install`; it must pass on atla and each gating VM (and rackhir
   at the close-out). Decide with the user where releases are published
   (GitHub releases on the project's repository, presumably) and whether
   they are signed.
   **Done (2026-10-02).** Decided with the user: a release is published
   as a GitHub release of `github.com/tkurtbond/peaseblossom` and on the
   user's own site too; it always has the tarball's SHA-256, and a GPG
   signature when the person releasing chooses to make one (`make
   dist-sign`, `gpg --armor --detach-sign` with the default key or
   `GPG_KEY`, into `<tarball>.asc`). A release: commit, `make check` on
   the gating hosts, `make stage2 distcheck` (which makes the tarball
   from HEAD), optionally `make dist-sign`, tag `v<version>`, and attach
   the tarball, `.sha256` (and `.asc`) to the GitHub release and the site.
   `make dist`
   writes `build/dist/peaseblossom-<version>.tar.gz` (3.1 MB) and its
   `.sha256`: HEAD's tracked files by `git archive` (so no build products
   or test outputs), the seed as `seed/`, and `COMMIT`, which
   `tools/build-info` reads where there is no `.git` (and it now takes a
   commit only from the tree's own repository, not one it was unpacked
   inside), so a tarball's poc names its commit. It refuses unless the
   tracked files are HEAD's and the Stage 2 poc that writes the seed names
   HEAD's commit. `make distcheck` unpacks it in a `mktemp` directory and, with
   `VOC_BIN_DIR` pointing nowhere, runs `make check-install` there: Stage
   0 from the seed, Stages 1 and 2, poc-rtl, install and the install
   checks.
6. **The User's Guide** (`doc/users-guide.md`): installing (packages,
   tarball, from git); a first program; the command line, task by task
   (building a program, compiling separately, `-O2`/`-OC`, `-opt`, `-g`,
   `-static`, `-link`, libraries and the library path, `-strict`,
   `-range-checks`, `-trap-location`); modules, imports and where poc looks
   for them; what a trap looks like and what each exit status means;
   debugging with gdb and lldb; calling C (`["C"]` procedures, a module's
   `.c` part); the runtime modules, with a short example each; moving a
   program from voc (what poc does differently, from `AGENTS.md` and the
   module headers). Every example in it is a file the test suite builds
   and runs (a fixture that extracts them, or the examples kept as files
   the guide includes), so the guide cannot go stale silently.
   **Done (2026-10-02).** `doc/users-guide.md`, eleven sections, the
   programs as files under `doc/examples/` (one directory per session).
   `tools/guide-examples check|update` reads two HTML-comment marks
   before a fenced block: `example: <file>` (the block must be the file)
   and `run: <dir>` (each `$ ` line runs, in one shell, in a fresh copy
   of the directory, and the other lines must be what they print);
   `update` writes the new output into the guide for its author to read.
   The fixture `doc-users-guide` runs `check`. The gdb session is shown,
   not run (no debugger on every host); the installing section's commands
   are not run either. `make install` puts the guide in `DOCDIR`. Writing
   the guide found and fixed: `-check` did not search libraries (so a
   module importing `Out` failed; it now reads a library's `.sym` files,
   though still no sources, and its "not found" notes name the library
   path), `-output-dir` with a build did not
   make the directory (now every command makes it, as `-library` did,
   and only one that cannot be made is an error), and a module missing its `END` name got a second
   error naming an empty one.
7. **The Reference Guide** (`doc/reference-guide.md`): what poc accepts
   and does, exactly, as a companion to `Oberon2.pdf`, which it refers to
   and does not reproduce. The basic types'
   sizes and ranges under each size model and target; every choice the
   report leaves to the implementation; every extension, from
   `doc/language-extensions.md`, and what `-strict` rejects; `SYSTEM`; the
   predeclared procedures' exact rules where poc pins them down (constant
   expressions, overflow, `DIV`/`MOD`, `ENTIER`, array assignment, `FOR`);
   the trap statuses; each runtime module's interface, procedure by
   procedure (from the modules' own comments, which this step checks and
   completes), and where it differs from voc's; every option and
   environment variable; the formats a user may meet (`.sym`, library
   manifests). And `poc(1)` (`doc/poc.1`, mdoc): the synopsis, every
   option, the environment, the files, the exit statuses, examples and
   pointers to the guides; `mandoc -T lint` clean, and checked to render
   with `man` on each host. Decided (user, 2026-10-02): where
   `doc/language-extensions.md` and the Reference Guide cover the same
   extension, `doc/language-extensions.md` is the design document (why,
   what was considered, how it is built) and the Reference Guide documents
   the extension as actually implemented (what a program can write and
   what it gets); each points to the other.
   **Done (2026-10-03).** `doc/reference-guide.md`, nine sections: the
   basic types, the implementation's choices, the extensions (each under
   its `doc/language-extensions.md` heading), `SYSTEM`, the exact rules,
   traps and exit statuses, the command line, files and formats (objects'
   keys, `.sym`, a library's directory and manifest), and the runtime
   modules. That last chapter is generated: `tools/rtl-reference
   check|update` (sh and POSIX awk, for the BSD hosts, which have no
   python3) writes, for each module of `rtl/llvm`, its header comment and
   its `poc -show-interface`, each declaration under the comment that
   precedes it in the source, between the guide's `<!-- rtl-reference
   begin/end -->` lines; the fixture `doc-reference-guide` runs `check`.
   Writing it completed the modules' comments (Files, Math, MathL, Texts,
   Platform, GarbageCollectedHeap, Modules, Oberon, In, Out, Err, Args,
   VT100 and the internal ones; a group of declarations shares one
   comment) and found: `-emit-interface` and `-show-interface` did not
   search libraries for imports either (as `-check` until step 6), so an
   rtl module's interface could not be shown; `-check` needs its imports
   compiled, which the User's Guide now says; and two rows of
   `doc/language-extensions.md` that predated D16 (locals zeroed) and
   `-range-checks`. `doc/poc.1` (mdoc) goes to `MANDIR/man1` and the
   guide to `DOCDIR`; `make check-install` renders the installed page
   with `man` and finds both guides.
8. **OS packages.** A Fedora RPM spec (built with `rpmbuild` on atla), a
   FreeBSD port (on alerik, with `poudriere` or `make package`), an
   OpenBSD port (on cymoril), and a pkgsrc package (on artos), each built
   from the release tarball, installed, run through `make check-install`
   against the installed files, and removed cleanly. Their dependencies
   are clang (the version each OS ships) and nothing else at run time.
   Decide with the user whether any is to be submitted upstream (that is
   outside this repository's control and is not this phase's exit
   condition).
9. **Exit gate.** From the release tarball, on atla and each gating VM:
   poc builds without voc, `make check` passes with the seed-built poc,
   `make install` and `make check-install` pass, the OS package installs
   and passes; rackhir at the close-out. The User's Guide's examples all
   run, `poc(1)` lints clean, and every option `poc` accepts appears in
   both `poc(1)` and the Reference Guide (a fixture compares them with the
   usage text).

**Testing summary**: steps 1 and 2 end in decisions recorded here;
steps 3-5 and 8 are install-and-run checks on each host; steps 6 and 7 are
checked by their runnable examples and the option cross-check of step 9.

### Phase 14 — Record and array literals, and structured constants

**Added 2026-10-02 (user)**, after Phase 13 and before the VAX/VMS work,
taking record and array literals out of the further extensions (now
Phase 19, where they were candidate 1, from Phase 11 A24). The later
phases moved up by one.

**Goal**: a value of a record or fixed array type written in an
expression, `Point{x := 1, y := 2}` and `Vector{1, 2, 3}`, in the LLVM
backend, with the front end's part shared by the VAX backend later.
`doc/record-and-array-literals.md` has the design: the decisions taken
with the user, the rules in detail, the survey of other dialects (Active
Oberon, Oberon+, Micron, Modula-3, ISO Modula-2, Ada, and those with
none; the first survey, 2026-09-26, is `doc/initializers-and-literals-
survey.md`), and what the implementation touches.

**Decided** (user, 2026-10-02): `T{...}`, the type always named; record
elements named only, `field := expression`; omitted elements take their
defaults (a field its initializer or zero, an array's later elements the
same, so an array of records gets its type's default records); no literal
of a record type with a field hidden or read-only where the literal is
written; and structured constants, `CONST origin* = Point{x := 0, y :=
0};` (user, 2026-10-02, reversing the first decision against them), so
`Types.Value`, the constant folder and the `.sym` format change too.
`-strict` rejects a literal.

**Steps**:

1. **The rules settled** in `doc/language-extensions.md` (a section
   "Record and array literals", with its one-line summary in `AGENTS.md`),
   from the design note: what a literal's type may be, the element rules,
   nested literals and when a nested one may leave out its type name,
   strings as elements, evaluation order, where a literal may stand, and
   type extension. Decide the open questions the note lists (indexed or
   repeated array elements, a literal of an open array type, inferring a
   bare `{...}`'s type), each "not in this phase" unless the user says
   otherwise.
2. **Front end**: a literal node in `SyntaxTree`; `Parser` reads
   `designator {` as a literal and a nested bare `{...}` as a list to be
   resolved; `SemanticActions` checks the type, each element's
   compatibility, repeated and unknown fields, the length, the visibility
   rule, resolves a bare `{...}` as a set or a literal by the expected type,
   and rejects a literal where it may not stand (a `VAR` parameter,
   `-strict`). **Testing**: `semantic-` fixtures accepting literals and
   rejecting each error, with their messages.
3. **Structured constants**: a structured `Types.Value`, folded by
   `ConstantEvaluator` from a constant literal and through selectors
   (`origin.x`, `table[3]`); a `CONST` declared by a literal, used as a
   read-only operand; an exported one written to the `.sym` file as its
   literal, every element given, in a `CONST` section after `TYPE`, and
   read back through the parser. The rules are the design note's
   "Structured constants", settled in step 1. **Testing**: `semantic-`
   and `module-` fixtures: folding, selection, rejection (a non-constant
   element, a `VAR` parameter, assignment, a hidden type exported), and a
   constant exported and imported.
4. **LLVM backend**: a record literal is an LLVM constant aggregate when
   every element is constant, otherwise an `insertvalue` chain over the
   record's defaults; an array literal a private constant global when
   constant, otherwise a stack temporary filled by stores, copied the way
   a string constant is. Omitted elements get the defaults `NEW` and
   variables get (field initializers, Phase 11 D17). Debug information
   needs nothing new. **Testing**: `llvm-` fixtures that build and run:
   records, arrays, nested literals, omitted elements and defaults, arrays
   of records, literals as value and open-array parameters, in variable
   and field initializers, of an extension assigned to its base, with
   pointers inside (and a collection while one is live), under both size
   models; and structured constants, local and imported, passed and
   indexed with a variable (each module's private copy); voc cannot
   cross-check any of them.
5. **Documentation**: the User's Guide (an example the suite runs) and
   the Reference Guide (Phase 13 step 7) describe literals and structured
   constants.
6. **Exit gate**: `make check` on atla and the gating VMs; Stage 1 and
   Stage 2 still reach their fixed point; rackhir at the close-out.

**Testing summary**: steps 2-4 add fixtures; step 6 is the usual gate.

### Phase 15 — VAX/VMS MACRO-32 backend (scoped, deferred, non-executable)
`VaxTypes.Mod`, `VaxCodeGenerator.Mod`, `VaxToolchainDriver.Mod` (stub
only — no assemble/link/run, per the locked-in decision).
**Explicit scope bound** (to prevent drift): targets exactly Phase 8's
narrow vertical-slice feature set (straight-line code, IF/WHILE/CASE,
arrays/records) — *not* full GC/dispatch parity. "Done" means
hand-reviewed `.mar` output checked into
`test/conformance/*/expected-vax.mar`-style fixtures with a reviewer
rationale comment, not an automated pass/fail. Assembling, linking and
running the output - under SIMH-hosted VMS 5.5-2, or real hardware - is
Phase 16's, which also lifts the vertical-slice bound above.

**Symbol-name mangling is required, not optional**: VAX MACRO-32 symbols
are limited to **31 characters**. This project's own naming convention
favors longer, descriptive Oberon-2 identifiers (module names, exported
procedure names, qualified `Module.Procedure` forms, type-bound-procedure
dispatch names), which will routinely exceed that limit — unlike the LLVM
backend, which has no such restriction and can emit names close to
verbatim. `VaxTypes.Mod`/`VaxCodeGenerator.Mod` must therefore implement a
deterministic name-mangling scheme (e.g. truncate-plus-hash-suffix) for
every emitted MACRO-32 symbol, and this scheme needs its own fixtures
(long/colliding names deliberately included in the Phase 15 test set) to
confirm two distinct Oberon-2 names never mangle to the same 31-character
symbol.

**External procedures under the VMS Calling Standard**: any procedure
declared external (Phase 6's FFI extension) must be lowered according to
VMS's own well-defined Calling Standard, not poc's internal calling
convention for ordinary Oberon-2 procedures — this is separate work from,
and in addition to, plain MACRO-32 codegen for pure-Oberon code, and its
external-symbol names are subject to the same 31-character limit above.

### Phase 16 — Running on VAX/VMS: assemble, link, run, and bootstrap poc there

**Goal**: the MACRO-32 Phase 15 writes is assembled, linked and run on
VAX/VMS 5.5-2 (a SIMH-hosted VAX, or real hardware), with just enough
runtime to compile poc itself, and poc - built for VAX/VMS - then compiles
its own source *on* VAX/VMS: the VMS counterpart of Phase 10's
self-hosting. This lifts two limits of earlier phases, which no longer
apply once it starts: the locked-in "assembling/linking/running is out of
scope" (Phase 15 stays what it was - hand-reviewed and non-executable -
and this phase is what runs it), and Phase 15's own scope bound to Phase
8's vertical slice, since poc's source uses far more than that.

**Explicit non-goals**: libraries beyond what poc's own source needs
(Phase 17); any VMS other than VAX 5.5-2 - no Alpha, Itanium, or later VAX
release, though nothing should be gratuitously specific to the exact
release; DECnet, DECwindows, layered products. Phase 17 owns shareable
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
   `expected-vax.mar` fixture Phase 15 checked in is assembled and run,
   turning "hand-reviewed" into automated pass/fail wherever the fixture
   is runnable; whatever the assembler rejects is a Phase 15 bug and is
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
   condition values); Phase 15 says external procedures use the standard
   and ordinary ones poc's own, and this step decides whether the
   hidden tag/length arguments and procedure values keep working that way
   or whether one convention for everything is simpler (Phase 17's AST
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
result, recorded in `doc/language-extensions.md` like the others.

**Candidates** (from `000-todo.org`'s Extensions list and Phase 11's
inventory):

Record and array literals, candidate 1 here until 2026-10-02 (Phase 11
A24, moved here 2026-09-26), are Phase 14 now.

1. **Slices of one-dimensional arrays** (`000-todo.org`).
2. **voc's read-only parameters, `x-`** (`000-todo.org`; considered and not
   adopted in Phase 11, `doc/language-extensions.md`).
3. **The terminator-based `ARRAY OF CHAR` assignment rule** (`000-todo.org`;
   decided against in Phase 11 A21, to reconsider).

**Exit gate**: every candidate has a recorded decision; each adopted one has
fixtures, is rejected by `-strict`, and passes `make check` on Linux and the
three BSDs (and, once Phase 16 exists, on VAX/VMS).

### Phase 20 — voc's library modules

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
