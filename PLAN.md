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

**Explicit non-goals**, unchanged from the phase-to-report-section map but
worth restating precisely since they bound every design choice below:
`POINTER`/`NEW`/GC, type-bound-procedure dispatch, open-array dope
vectors, full `Out.Mod`/`In.Mod`. **Correction to this file's earlier
wording**: Appendix D5's tag/ProcTab/BaseTypes layout was previously
listed under Phase 8's `LLVMTypes.Mod`; it has no reason to exist before
dispatch does and is moved to Phase 9 below. In scope: fixed-size
arrays/records (as values, never behind a pointer), straight-line code,
module-level and local `VAR`s, ordinary (non-type-bound) `PROCEDURE`s,
IF/CASE/WHILE/REPEAT/FOR/LOOP+EXIT/RETURN, and the subset of §10.3
predeclared procedures that don't presuppose `POINTER`/`NEW` (`ABS`, `ODD`,
`CHR`, `ORD`, `CAP`, `LEN`, `INC`, `DEC`, `COPY`, `HALT` — not `NEW`,
`DISPOSE`, or anything `SYSTEM.*`).

**Proposed build order** — each numbered step lands its own conformance
fixtures before the next starts, matching every earlier phase's
incremental style. Three design choices below are marked **Decided**
(confirmed 2026-09-18): clang single-step build (step 1), LLVM-native
struct/array layout plus a cross-check fixture rather than manual packing
(step 4), and a fixed rtl module set first, with general multi-module
`IMPORT` linking deferred to step 12 (step 6).

1. **Toolchain smoke test, no `poc` code involved.** Hand-write a trivial
   `.ll` "hello world" and drive it through the real toolchain on this
   machine to settle the invocation strategy before any codegen exists to
   depend on it. **Decided**: `LLVMToolchainDriver.Mod` shells to `clang
   foo.ll -o foo` directly, one step — clang accepts `.ll` input and
   handles assembling+linking itself. `llc -S` is reserved as an
   optional, separate `-dump-asm`-style debug aid for reading generated
   assembly in golden-file tests, not part of the normal build path. This
   step also confirms `llc`/`clang` are actually installed and records
   their versions/default target triple in `AGENTS.md`, the same way
   `voc_toolchain`-style version pinning is already tracked for `voc`.

2. **CLI and driver scaffolding**, codegen still stubbed. `Poc.Mod` gains
   `-emit-llvm-ir <file>` (write textual `.ll` only, no toolchain call —
   portable/CI-safe, the LLVM analogue of `-emit-interface`) and `-o
   <path>` (full build via `LLVMToolchainDriver.Mod`, invoking the step-1
   pipeline). Add a `-target <triple>` flag, default to the host triple
   (auto-detected once via the installed `clang`, cached); `LLVMTypes.Mod`
   derives word size (32 vs. 64) from a small table of recognized arch
   prefixes in the triple rather than a separate flag, since the triple is
   already the single source of truth `clang`/`llc` themselves consume.
   The already-implemented `-O2`/`-OC` size-model flag is reused unchanged
   for elementary-type sizing — Phase 8 is its first real consumer beyond
   `-dump-layout`. Validate the whole pipeline with a stub
   `LLVMCodeGenerator.Mod` that emits a fixed, hand-written "hello world"
   `.ll` regardless of input, so the CLI/driver/test-harness plumbing is
   exercised before any real tree-walking codegen exists — the same
   "harness before logic" sequencing Phase 0 used for `testenv.sh`.

   **Implemented 2026-09-18.** `src/back/llvm/LLVMCodeGenerator.Mod`
   (the stub described above - `Generate*(module, scope, triple, w:
   Files.Rider)` writes straight to a caller-opened `Files.Rider`,
   matching `ModuleInterface.Write*`'s own style rather than building an
   in-memory string) and `src/back/llvm/LLVMToolchainDriver.Mod`
   (`HostTriple*`, `EmitIR*`, `Build*`) both added; `tools/bootstrap/
   stage0` extended to compile them. Two CLI-grammar decisions not fully
   pinned down by this file's original wording, resolved during
   implementation: (1) `-o <path>` is a *flag*, parsed in `Run`'s
   existing flag-scanning loop exactly like `-output-dir`/`-target`
   itself, not a command in its own right - the command that consumes it
   is a new `-build <file>`, giving the CLI grammar `poc -o <exe> -build
   <file>` (clang's own `-o` convention, adapted onto poc's existing
   "flags before a command word" shape rather than clang's "flags
   anywhere around positional source files" shape); `-build` without a
   preceding `-o` is a reported error (`-build has no default`), not a
   derived-name fallback. (2) `HostTriple*` shells `clang -dumpmachine`
   via `Platform.System`, redirected to a PID-scoped scratch file under
   `/tmp` (`Platform.Mod` exposes no dedicated temp-directory accessor),
   then reads that single line back with `Files.Old`/`Files.ReadLine` -
   `Platform.System` has no stdout-capture mode of its own, only a
   process exit code, so this is the only way to get its output back
   into poc's own address space without a real pipe/fork primitive -
   confirmed by inspecting `Platform.Mod`'s full exported procedure list
   directly (its installed `.sym`/build-generated `.h`, not `showdef`,
   which wasn't run for this): no `Popen`/`Pipe`/`Fork`/`Exec`-shaped
   export exists, only `System`. `LLVMTypes.Mod`
   and its word-size-from-triple table are genuinely **not** built yet -
   nothing in step 2's own scope needs word size (the stub ignores its
   inputs entirely), so that's deferred to step 4 as originally planned,
   not implemented early. Two new conformance fixtures: `llvm-emit-ir`
   (golden-diffs the stub's `.ll` output against a fixed, non-host
   `-target` so the fixture doesn't depend on which machine's `clang`
   auto-detection ran) and `llvm-build-run` (the first real
   compile+link+run+diff fixture in this suite - relies on real
   auto-detection and an actual `clang` invocation, diffing the running
   binary's own stdout). All 96 conformance tests pass (94 prior + these
   2).

3. **Test harness generalization.** `test/testenv.sh` was already
   parameterized over a `BACKEND` variable back in Phase 0 (later
   simplified away once it had nothing to select between — see the
   project-overview memory of that decision) but never actually exercised
   for LLVM. Reintroduce it properly here: a `BACKEND=llvm` fixture mode
   invokes `poc -o`, runs the resulting binary, and diffs captured stdout
   against `expected`, alongside the existing type-check-only and
   voc-comparison modes.

   **Implemented 2026-09-18, revised.** Re-examined the `BACKEND`
   variable this step's own wording anticipated reintroducing, now that
   the LLVM backend actually exists — and found it still isn't needed.
   Phase 1's simplification (removing Phase 0's original `BACKEND`
   case-statement) put both `voc` and `poc`'s own build on `PATH`
   unconditionally, so every fixture already names whichever compiler it
   wants directly; `llvm-build-run` (step 2) already does this, calling
   `poc` by name exactly as every `voc`-based fixture calls `voc` by
   name — there was never a per-test "which backend" choice for a
   variable to make. What step 3 actually needed, and now has, is
   `test/testenv.sh`'s new `poc_build_run` shell function: the one
   genuinely new *repeated pattern* LLVM fixtures introduce (`poc -o
   <exe> -build <file>`, then run `<exe>`), now centralized so future
   compile+link+run+diff fixtures (steps 6 and 13) don't each hand-roll
   the exact clang-backed CLI incantation. `poc_build_run` names its
   executable after the fixture's own directory
   (`$(basename "$PWD")`), matching `test/conformance/hello`'s existing
   convention for `voc`'s `-m` build — this also fixed a real, if minor,
   correctness gap in step 2's own `llvm-build-run` fixture, which had
   named its executable `llvm-stub-out` (not matching its directory), so
   `testenv.sh`'s existing `rm -f ... "$(basename "$PWD")"` cleanup line
   never actually removed it between runs; a failed rebuild could have
   silently re-run a stale binary from a previous pass. `llvm-build-run`
   migrated to call `poc_build_run` and its golden `expected` file/
   `.gitignore` entry updated to match. All 96 conformance tests pass.

4. **`LLVMTypes.Mod`.** Oberon type → LLVM type for the in-scope type set
   only (basic types, fixed arrays, records — no pointer/procedure types
   yet beyond what external-procedure declarations need). **Decided**:
   let LLVM's own struct/array types lay themselves out naturally for the
   target data layout (simpler, and it's LLVM's job) rather than manually
   forcing byte offsets to match `MemoryLayout.Mod`'s own hand-computed
   offsets; add a dedicated cross-check fixture per composite-type test
   case instead, comparing `MemoryLayout.Mod`'s computed field offsets
   against `llvm-as`/a tiny probe program's actual `sizeof`/offset
   results — a regression test for layout *agreement*, not a
   manual-packing mechanism.

   **Implemented 2026-09-18.** `src/back/llvm/LLVMTypes.Mod` adds
   `TypeString*(t, sizeModel, VAR result)`, covering exactly Phase 8's
   in-scope type set (basic types, fixed arrays, base-less records) and
   returning the literal string `"<unsupported>"` for anything else
   (POINTER, PROCEDURE, open arrays, record extension) rather than
   failing — nothing calls it with one of those yet, so a total function
   was simpler to reason about than a partial one. Fixed arrays/records
   become literal, anonymous LLVM types (`"[n x T]"` / `"{ T1, T2, ... }"`)
   with no offsets computed by this module at all, per this step's own
   "Decided" note above — `TypeString*` does not vary by target word
   size (none of Phase 8's in-scope types are word-size-dependent; only
   POINTER/PROCEDURE are, and both are out of scope). Golden-diffed via
   `Poc.Mod`'s new `-dump-llvm-types <file>` command and the
   `llvm-types-dump` conformance fixture (mirrors `-dump-layout`/
   `layout-node-tree`'s role exactly, but only the O2/OC size-model axis,
   not word size).

   `LLVMTypes.Mod` also adds `WordSizeForTriple*(triple, VAR wordSize):
   BOOLEAN`, recognizing an LLVM target triple's arch component — not for
   `TypeString*` itself, but for a different, real consumer:
   `ConstantEvaluator.Mod`'s pre-existing, already-documented gap that
   `SIZE(T)`/`MAX(T)`/`MIN(T)` folding stayed hardcoded to
   `MemoryLayout.wordSize32` "until a real target/word-size choice
   exists" — now that `-target` resolves a real triple (step 2),
   `ConstantEvaluator.Mod` gained a `wordSize*` module `VAR` and
   `SetWordSize*` setter (mirroring its existing `sizeModel*`/
   `SetSizeModel*` pattern), and `Poc.Mod` wires
   `LLVMTypes.WordSizeForTriple*` into that setter — for `-emit-llvm-ir`/
   `-build` unconditionally (via `SetWordSizeFromTriple`, called right
   after `ResolveTriple` and before parsing, so `CheckModule`'s constant
   folding sees it), and for `-emit-interface` only when the caller
   passes `-target` explicitly, so that command keeps its pre-existing
   "no clang required" behavior by default (`ResolveTriple`'s
   auto-detect fallback is the only path that needs clang; an explicit
   `-target` never reaches it). An unrecognized arch is not an error —
   word size just stays at whatever it already was, the same fallback
   `SIZE(T)` already had. Verified end to end with an exported
   `CONST s* = SIZE(P)` (`P` a `POINTER` type) compiled via
   `-emit-interface -target i686-unknown-linux-gnu` (`s* = 4`) vs.
   `-target x86_64-unknown-linux-gnu` (`s* = 8`) vs. no `-target` at all
   (`s* = 4`, the `wordSize32` default) — the `.sym` file makes a folded
   `CONST`'s numeric value directly observable, which neither `-check`
   nor `-emit-llvm-ir`/`-build` (no codegen for constant values exists
   yet) can do.

   The `llvm-layout-cross-check` fixture (`mixed.mod`, a `RECORD` mixing
   a 1-byte `CHAR`, two 8-byte `HUGEINT`/`LONGINT`-under-OC fields, and a
   2-byte `SHORTINT`-under-OC field to force non-trivial OC-model
   padding) empirically confirms `MemoryLayout.Mod`'s hand-computed
   offsets agree with LLVM's own target-datalayout-driven layout
   algorithm for real x86 targets, via
   `clang -Xclang -fdump-record-layouts -ffreestanding -target <triple>
   -c <file>.c -o <file>.o` — a real, ABI-verified struct layout dump
   requiring no linking or running (and no target sysroot/multilib,
   thanks to `-ffreestanding` plus hand-rolled `int8_t`/`int16_t`/
   `int64_t` typedefs standing in for `<stdint.h>`, which needs
   `gnu/stubs-32.h` for `-target i686-...` that this host doesn't have
   installed). Confirmed for a C struct with the OC-model-equivalent
   fixed-width fields at both `i686-unknown-linux-gnu` (`sizeof=24,
   align=4`, offsets 0/4/12/16 — matching `sizeOC_32`/`offsetOC_32`
   exactly) and `x86_64-unknown-linux-gnu` (`sizeof=32, align=8`, offsets
   0/8/16/24 — matching `sizeOC_64`/`offsetOC_64` exactly), including the
   specific empirical fact (found while working out this technique) that
   an 8-byte field only gets 4-byte alignment inside a struct on 32-bit
   x86, matching `MemoryLayout.Align`'s "natural alignment capped at word
   size" rule precisely. This validation is one-time and static (the
   algorithm being checked is deterministic compiler code, not something
   that drifts per test run) — the fixture itself only runs `poc
   -dump-layout`, with the clang-verified numbers encoded directly into
   its golden `expected` file, so `make test` keeps no runtime clang
   dependency for this fixture (matching `layout-node-tree`/
   `layout-size-model`, and unlike `llvm-emit-ir`/`llvm-build-run`, which
   genuinely need the toolchain at test time).

   One real bug found and fixed along the way: `TypeString*`'s `result`
   parameter is `VAR result: ARRAY OF CHAR` — an open-array `VAR`
   parameter. Its length is a genuine run-time value (voc's calling
   convention passes an open array's actual length to the procedure as a
   hidden parameter, so it *is* known inside the procedure at run time),
   but that length isn't part of `result`'s own type — and that's what
   actually matters: Oberon2.pdf's assignment-compatibility rule 6 lets a
   string constant be assigned via `:=` only to a *fixed-size*
   `ARRAY OF CHAR` variable, one whose length is fixed by its own
   declaration rather than by whatever's passed at a given call. An
   open-array formal parameter's type is never fixed-size, however well
   its length is known at run time, so rule 6 still doesn't apply — every
   `result := "<literal>"` in the module (originally ~16 of them) had to
   become `COPY("<literal>", result)` instead. `Diagnostics.Mod`'s own
   `Reset*` hits the mirror-image failure of the same rule (a *variable*,
   not a constant, on the right-hand side — rule 6 only ever covers a
   literal string constant — assigned into a fixed-size array field).
   All 98 conformance tests pass (96 plus the two new fixtures above).

5. **Straight-line codegen: the smallest useful slice.** Module-level
   `VAR`s as LLVM globals, local `VAR`s as `alloca`s, arithmetic/
   relational/boolean expression evaluation to SSA form, assignment
   statements. First target: a module whose entire body is a `BEGIN...END`
   init block doing arithmetic, no calls, no output yet — verified only by
   inspecting/golden-diffing the emitted `.ll`, since there's nothing to
   print until step 6.

   **Implemented 2026-09-18.** `src/back/llvm/LLVMCodeGenerator.Mod`'s
   step-2 stub is replaced with real tree-walking codegen, deliberately
   narrower than this step's own header text anticipated in two ways,
   both documented directly in the module's own header comment rather
   than silently: no `alloca`s (there are no local `VAR`s to put in one —
   Oberon-2 only has *module*-level and *procedure*-level `VAR` sections,
   and procedures don't exist until step 10, so "local `VAR`s as
   `alloca`s" has nothing to apply to yet), and REAL/LONGREAL arithmetic
   is out of scope even though `Types.IsNumeric` accepts it — every
   "is this arithmetic operand handled" check in the new code
   deliberately uses `Types.IsInteger*` (`SHORTINT`..`HUGEINT` only), not
   `Types.IsNumeric*`, specifically to route `REAL`/`LONGREAL` to the
   same `"; unsupported: ..."`-comment-plus-well-typed-placeholder
   fallback every other out-of-scope construct gets (procedure calls,
   `IF`/`WHILE`/etc., array/record field access) — because a nonzero
   `REAL`/`LONGREAL` literal needs a verified-safe decimal-to-LLVM-text
   conversion that doesn't exist yet: `ModuleInterface.Mod`'s
   `FormatRealMagnitude` already solves the adjacent "round-trip safely
   through Oberon's own `ParseReal`" problem for `.sym` files, but has
   not been verified against LLVM's own (APFloat-based) decimal literal
   parser, nor adapted to LLVM's `e`/`E`-only exponent syntax (no
   Oberon `D0` suffix) — deferred as its own increment rather than
   built, and left unverified, as a side effect of this one.

   In scope, and implemented: module-level `VAR`s of any Phase-8 type
   become `@<ModuleName>.<name>` LLVM globals (`zeroinitializer` —
   costs nothing extra even for array/record `VAR`s, though nothing
   reads/writes their fields until step 8); assignment statements
   targeting a bare, unqualified, selector-free module `VAR`; and
   expressions built from integer/`CHAR` literals, bare `VAR`/`CONST`
   designators (a `CONST`'s value is already fully folded by
   `ConstantEvaluator.Mod` — formatted directly as an LLVM immediate,
   never loaded from memory, since Oberon `CONST`s have no runtime
   storage at all), unary `+`/`-`/`~`, and binary `+ - * DIV MOD` /
   `= # < <= > >=` / `& OR` — for the `SHORTINT`..`HUGEINT` integer
   family, `CHAR`, `BOOLEAN`, and `SET`. Every live codegen value is
   carried at its full `LLVMTypes.TypeString*` width (`i8` for
   `BOOLEAN`/`CHAR`, `i16`/`i32`/`i64` for the integer family per
   `-O2`/`-OC`, `i32`/`i64` for `SET`) — `i1` only ever appears as
   `icmp`'s immediate result, `zext`'d to `i8` in the same instruction
   group that produced it, trading a handful of avoidable `zext`s for
   never having two representations of the same kind of value. Mixed-
   width integer arithmetic/assignment (e.g. `SHORTINT + INTEGER`, or
   assigning an `INTEGER`-typed expression into a `LONGINT` `VAR`)
   widens via `sext` up to `Types.WiderOf*`'s result — verified in a
   scratch fixture with `sa: SHORTINT; wide: LONGINT; wide := sa + a`
   (`a: INTEGER`), producing exactly `sext i8 → i16` then `sext i16 →
   i32`, matching Appendix A's numeric-inclusion widening rule exactly.

   `DIV`/`MOD` lower Oberon-2's *floored* division semantics — not
   assumed, confirmed 2026-09-18 against real `voc` first (this
   project's standing practice): `(-7) DIV 2 = -4`, `(-7) MOD 2 = 1`,
   `7 DIV (-2) = -4`, `7 MOD (-2) = -1`, `(-7) DIV (-2) = 3`,
   `(-7) MOD (-2) = -1` — the remainder's sign always matches the
   divisor's, exactly the report's own
   `x = (x DIV y)*y + x MOD y, 0 <= x MOD y < y` (for `y > 0`; `y < x MOD
   y <= 0` for `y < 0`) definition, i.e. genuine floored division, not
   the truncating division LLVM's own `sdiv`/`srem` implement (those
   truncate toward zero, like C). `GenerateDivMod` derives floored
   `DIV`/`MOD` from `sdiv`/`srem` via the standard correction — adjust by
   1/by the divisor whenever the truncated remainder is nonzero and has
   a different sign than the divisor — expressed with LLVM's `select`
   instruction rather than a branch, so this step's codegen stays
   genuinely straight-line (no basic blocks/labels anywhere). `&`/`OR`
   are lowered *eagerly* (plain `and`/`or` on the operands' already-
   computed `i8` values), not with Oberon-2's required short-circuit
   evaluation — a deliberate, documented simplification, not a latent
   bug: nothing this step's codegen can itself construct has a side
   effect or a trap (no calls, no array/pointer access exist yet), so
   eager and short-circuit evaluation are observably identical for every
   expression reachable today; revisit once step 6 (calls) or step 8
   (array access) make the difference observable, at which point real
   short-circuiting will need this module's first actual basic
   blocks/branches.

   `ConstantEvaluator.ParseCharConst` gained a `*` export mark (previously
   private), for the same reason `IntegerLiteralType*`/`ParseReal*`
   already had one: `LLVMCodeGenerator.GenerateLiteral` needs a `CHAR`
   literal's actual value, and this is a pure, context-free lexeme
   parser (no `Scope`, no diagnostic), not a constant-*expression*
   evaluator — reusing it is the same kind of front-end reuse the other
   two already established, not a new layering violation.
   `ConstantEvaluator.Evaluate*` itself is deliberately **not** reused for
   live (non-`CONST`) subexpressions — it rejects any designator that
   isn't `constClass` with a real diagnostic ("not a constant"), so
   calling it on a tree containing a live `VAR` reference would corrupt
   `Diagnostics.errorCount` after the module already checked out clean.

   No new module-level correctness gaps found this step (unlike steps 3/
   4's own real bugs) — the one real mistake, `WriteStr(w, "..." + "...")`
   (attempting the C-style string-literal concatenation Oberon-2 doesn't
   have, in one `Unsupported` fallback's message), was caught immediately
   by `voc`'s own parser during the first compile attempt, never reached
   runtime.

   Verification went beyond golden-`.ll`-diffing alone: PLAN.md's own
   text for this step assumed correctness could only be *inspected*,
   since there is still no `Console`-style output until step 6 — but
   exit codes need no I/O at all. During development (not as a permanent
   fixture), a scratch module's generated globals were inspected directly
   by linking its `.ll` (with its own generated `@main` stripped) against
   a small hand-written C harness that called `<Module>_init()` and
   `printf`'d every global afterward — confirming every one of the
   arithmetic/relational/boolean/`SET` operators above against hand-
   computed expected values, not just plausible-looking IR. Two real
   fixture-authoring mistakes surfaced this way, both about *this
   step's own scope boundary*, not the codegen itself: a double-quoted
   `"A"` lexes as a `STRING` literal even at length 1 (Oberon-2's real,
   separate single-char-string-to-`CHAR` assignment-compatibility rule,
   deferred alongside array/string support to step 8 — fixed by using
   proper `41X`-style `CHAR`-literal syntax instead), and a `{0,1,2,5}`
   `SET` constructor expression is `SyntaxTree.SetExprNode`, whose live
   (non-`CONST`) construction this step also doesn't lower — fixed by
   moving the same set literals into `CONST` declarations instead (a
   `CONST`'s already-folded value reaches codegen through the ordinary
   designator path, `GenerateConstValue`, with no `SetExprNode` codegen
   needed at all).

   Two conformance-fixture updates were required, not just additions,
   since `llvm-emit-ir`/`llvm-build-run` (step 2) both depended on the
   now-removed stub's fixed behavior: `llvm-emit-ir`'s `stub.mod` keeps
   its trivial empty body (still the right minimal case for exercising
   CLI/file-writing plumbing alone) but its golden `expected` now reflects
   real (if content-free) codegen's actual `@llvmStub_init`/`@main`
   output instead of the old hand-written "Hello, world!" stand-in;
   `llvm-build-run` similarly now expects the built binary to run
   successfully and print *nothing* (no FFI exists yet to print
   anything), rather than the stub's hardcoded greeting. A new,
   dedicated fixture, `llvm-straight-line-arithmetic`, golden-diffs
   `-emit-llvm-ir`'s real output for the arithmetic/relational/boolean/
   `SET` module described above (the same one manually verified via the
   C-harness technique) — a pure `.ll` diff, matching this step's own
   "verified only by inspecting/golden-diffing" plan text, since
   `llvm-build-run`-style execution still has nothing observable to
   check until step 6. All 99 conformance tests pass (98 prior, two
   updated, one new).

6. **External-procedure FFI lowering + `rtl/llvm/Console.Mod`.**
   `LLVMCodeGenerator.Mod` emits an LLVM `declare` plus a C-calling-
   convention `call` for every `PROCEDURE ["C"] ...` declared external
   (Phase 6's FFI extension, its first real consumer per the existing
   text below). `rtl/llvm/Console.Mod` is written using this mechanism —
   proposed minimal interface `PrintString(s: ARRAY OF CHAR)` and
   `PrintLn`, implemented by declaring libc's `write(2)` externally
   (portable across Linux/the BSDs; avoids pulling in buffered-stdio
   semantics `printf`/`puts` would add). This is also where a minimal
   `rtl/llvm/Runtime.Mod` (or a few more exports on `Console.Mod`) is
   needed for `HALT` and for the runtime traps codegen will need in step
   9 (index-range, no-matching-`CASE`-label) — an external-linked
   `write`+`exit` abort path, matching voc's own halt-code convention (see
   the `ASSERT` open design question above). **Decided**: start with a
   *fixed* rtl module set (just `Console.Mod`, maybe `Runtime.Mod`)
   alongside the one user module under test — general multi-user-module
   `IMPORT` linking (transitively compiling every user-authored import
   found via `ModuleInterface.Mod`, not just this fixed rtl set) is real,
   valuable Phase 8 scope but lands later, as its own step (12), rather
   than blocking the first runnable program. First genuine "hello world"
   fixture (compile+link+run+diff stdout) lands here.

   **Implemented**, with one real design revision along the way: a
   dedicated `rtl/llvm/Console.Mod` wrapper (`PrintString`/`PrintLn`
   calling `write` internally) needs ordinary, non-external procedure-
   with-body codegen to compile its own wrapper bodies — genuinely step
   10's scope, not yet built. Rather than block step 6 on step 10, this
   step instead proves the FFI `declare`/`call` mechanism directly: its
   own milestone fixture, `llvm-hello-world`, declares
   `PROCEDURE ["C", "write"] SysWrite(...)` and calls it itself, with no
   `Console.Mod` in between — `Console.Mod`'s real wrapper body is
   deferred to (folded into) step 10. `SemanticActions.Mod`'s external-
   procedure front end (Phase 6) needed no changes at all — confirmed by
   `poc -check` on a scratch fixture before writing any codegen — so this
   step is pure backend work: `EmitExternalDeclares` emits an
   unconditional LLVM `declare` for every `PROCEDURE [conv] ...`
   external declaration the module has (whether or not it's actually
   called — there's no "used externals" set built to check against, and
   an unused `declare` is harmless), and `GenerateCall`/
   `GenerateExternalCall` lower a call through it: `VAR` actual arguments
   pass as the address of a bare module-`VAR` designator (`ptr
   @Module.name`, the same reference `GenerateDesignatorValue` already
   loads from); an `ARRAY OF CHAR` value parameter only handles a literal
   string-constant actual argument, materialized as its own private
   global constant and passed as a bare `ptr` (deliberately *not* the
   hidden-length-parameter convention Oberon-internal open-array value
   parameters need — a C-ABI external declaration's real callee has no
   room in its prototype for one); every other parameter shape passes by
   value, `sext`-widened via the existing `ExtendTo` where the parameter
   type is a wider integer. Every declared external procedure's "VMS"
   calling convention (Phase 6's third option, besides "C" and none) is
   parsed and recorded but not specially handled yet — treated like "C",
   wrong but harmless until Phase 13 gives it a real, different lowering.

   A string-literal argument's global needs a name derivable
   independently by two separate, uncoordinated passes — a pre-pass,
   `CollectStringConstantsSeq`, walks the module's own statement/
   expression tree once to emit every string-literal global *before* any
   function body is written (required because LLVM tolerates a global
   definition appearing anywhere relative to its uses, but never nested
   inside a `define ... { ... }` body, and this module's `Files.Rider`
   writes strictly sequentially with no way to insert content out of
   order later), and the real codegen pass re-encounters the same
   literals later and must reference the identical global. Solved by
   naming each string constant from its own source position
   (`@.str.L<line>.C<column>`) rather than a shared counter, so both
   passes derive the same name with no mutable state threaded between
   them.

   A real, load-bearing ABI-correctness gap surfaced and is deliberately
   left open, not solved: this project has no target-native "C
   `int`"/"`size_t`"-equivalent Oberon type that varies by triple the way
   C's own types do. `HUGEINT` is always LLVM `i64` regardless of target
   word size (`LLVMTypes.BasicTypeString`) — correct for `write(2)`'s
   `size_t count` on a 64-bit x86 target, but not on `i686-...` or
   similar. `llvm-hello-world`'s own header comment documents this
   explicitly: its Oberon parameter types (`LONGINT` for `write`'s `int
   fd`, `HUGEINT` for its `size_t count`) were hand-picked to match real
   `write(2)`'s C ABI only for a 64-bit x86 target — `LONGINT` happens to
   be LLVM `i32` under this project's default `sizeModelO2`, matching
   C's 32-bit `int`, but that's this step's default, not something an
   external declaration's author is guided toward or warned about if it
   doesn't hold.

   Two real bugs were found and fixed this step, neither caught by any
   existing golden-file fixture (both surfaced only while dogfooding
   `llvm-hello-world` itself during development):

   - `CollectStringConstants`'s own recursive descent (`WITH expr:
     SyntaxTree.UnaryExprNode DO ... | expr: SyntaxTree.BinaryExprNode DO
     ...`) originally called itself directly from inside those `WITH`
     branches — hitting a known, already-documented `voc` compiler bug
     (see `AGENTS.md`'s "Known `voc` bugs affecting `poc`'s own source"):
     a procedure calling *itself* from inside one of its own `WITH`
     branches is misdiagnosed `err 113 incompatible assignment`, even
     when the argument's type is fine. Worked around exactly as that
     entry recommends: each `WITH` branch now only stashes the child
     subexpression(s) it needs into local variables, and the actual
     recursive calls happen after the `WITH` block closes (harmless when
     a branch leaves a child variable `NIL`, since `CollectStringConstants`
     already treats a `NIL` argument as a no-op).
   - `GenerateCallArgList` originally wrote each argument's `"type text"`
     pair directly to the output stream while the caller had already
     started (but not finished) writing the `"call ...("` line itself —
     but evaluating a non-`VAR`/non-string argument can itself need to
     emit a whole separate instruction line first (e.g. `ExtendTo`'s
     `sext`, via `GenerateExpr`'s own ordinary "write instructions as you
     go" style). Emitting that instruction line while a `"call ...("`
     line was only half-written spliced a bare `%tN = sext ...`
     instruction into the middle of the call's own parenthesized argument
     list, producing syntactically invalid LLVM IR — caught immediately
     by inspecting `llvm-hello-world`'s own generated `.ll` by hand, not
     by any test failure (nothing prior exercised a call needing an
     integer-widening argument). Fixed by making argument evaluation and
     argument-list *writing* two strictly separate phases:
     `GenerateCallArgList` now evaluates every argument first (emitting
     any instructions to `w` as it goes) and builds the full, already-
     joined `"type text, type text, ..."` text into a caller-owned
     buffer, and only after every argument is fully evaluated does
     `GenerateExternalCall` write the `"call ...("` line itself, in one
     unbroken sequence of `WriteStr` calls with no interleaved
     instruction output possible.

   `EmitExternalDeclares`/`CollectStringConstantsSeq` also each briefly
   introduced two unconditional trailing blank lines even for a module
   with no external declarations and no string literals (a `WriteLn`
   after each section regardless of whether it emitted anything),
   regressing `llvm-emit-ir`'s golden diff by two extra blank lines
   before `define`; fixed by removing each section's own `WriteLn` and
   keeping exactly one, unconditional blank line right before the
   `define` line, the same single-blank-line behavior `EmitGlobals`
   already had for an empty module.

   Verified beyond the golden-`.ll`-diff style steps 1–5 used: `poc -o
   llvm-hello-world -build hello.mod` actually compiles, links (via
   `clang`, `LLVMToolchainDriver.Build`), and runs, printing the real
   string `Hello, world!` to stdout — the first genuine compile+link+
   run+diff-stdout fixture in this suite, using `testenv.sh`'s
   `poc_build_run` helper exactly as `llvm-build-run` (step 3) already
   established the pattern for. Also confirmed, via a scratch (not
   committed) fixture calling a locally-declared, non-external
   `PROCEDURE`, that `GenerateCall`'s fallback for a real Oberon-2 shape
   this step still doesn't lower degrades cleanly to `Unsupported`
   (`"non-external procedure calls (PLAN.md Phase 8 step 10+)"`) rather
   than emitting a call to an undeclared symbol or crashing the
   generator. All 100 conformance tests pass (99 prior, one new).

7. **Control flow.** IF/CASE/WHILE/REPEAT/FOR/LOOP+EXIT/RETURN lowered to
   basic blocks and branches.

   **Implemented.** This is the module's first genuinely basic-block-
   producing step - every prior step's codegen wrote into one unlabeled
   `entry:` block only. Every new statement generator
   (`GenerateIfStatement` onward) shares one invariant that makes the
   whole thing compose with zero backpatching: whenever a generator
   returns, the writer is positioned inside a fresh, still-open
   (unterminated) block - the "join"/"end" label it just wrote.
   `GenerateStatementSeq` itself stays completely ignorant of control
   flow as a result; it just keeps calling `GenerateStatement` for the
   next statement in the list, and whatever block that instruction lands
   in is already the right one, because everything is emitted in strict
   program order. `GenerateExitStatement`/`GenerateReturnStatement` (hard
   terminators, no fallthrough of their own) keep the same invariant by
   opening a fresh - if unreachable - block right after their own
   terminator, so that dead code textually following a RETURN/EXIT
   (legal Oberon-2, just pointless) still lands somewhere syntactically
   valid instead of after an already-terminated block's terminator.

   IF lowers its `IfBranchNode` chain iteratively (elsif falls through to
   the next branch's own test), not recursively - this project's own
   front end has no WHILE-ELSIF form at all (`Parser.Mod` only ever
   parses a single condition/body for WHILE), confirmed against
   `Oberon2.pdf` itself (`WhileStatement = WHILE Expression DO
   StatementSequence END` — no ELSIF there either, unlike `IfStatement`,
   which the report's own grammar does give one), so IF is the only
   construct here that needed an elsif chain. CASE lowers each case's
   label list (which may mix single values and ranges, e.g. `1, 3..5,
   9:`) into a chain of `icmp`/`and`/`or` range tests reusing the exact
   same iterative "test, then, else" shape as IF, rather than LLVM's own
   `switch` instruction - `switch` only matches exact values, and a CASE
   label range (`CaseLabels = ConstExpression [".." ConstExpression]`,
   confirmed against `Oberon2.pdf` 9.5) needs a real `>=`/`<=` pair, not
   an enumeration. `Oberon2.pdf` 9.5's own "if the value of the
   expression does not occur as a label of any case,... the program is
   aborted" (when there's no ELSE) is PLAN.md Phase 8 step 9's own job
   ("CASE-without-matching-label") - this step just falls through with
   no effect in that case, exactly as if it were a final, unconditional,
   empty ELSE, matching how every other construct here lands ahead of
   its own eventual step 9 trap.

   FOR is lowered exactly per `Oberon2.pdf` 9.8's own stated equivalence
   (confirmed by reading the report directly, not assumed): `v := low;
   temp := high; IF step > 0 THEN WHILE v <= temp DO statements; v := v
   + step END ELSE WHILE v >= temp DO statements; v := v + step END END`
   - `stop`/`temp` is evaluated once, before the loop, exactly as the
   report's own "temp := high" shows (not re-evaluated per iteration);
   its computed register value is simply reused directly in the loop
   header on every iteration with no `phi` node or memory spill needed,
   since it is defined exactly once in the block that dominates every
   one of its uses (the loop preheader dominates the header, which
   dominates the body/back-edge) - ordinary SSA reuse across blocks,
   nothing loop-specific about it. `step`'s sign, needed to choose `<=`
   vs. `>=`, is resolved once at Oberon-*compile*-time via
   `ConstantEvaluator.Evaluate` rather than compared at IR run time - the
   report's own "IF step > 0" is itself already a compile-time fact here,
   since `CheckForStatement` already guarantees `step` folds to a nonzero
   integer constant (§9.8) before codegen ever runs. The control variable
   itself is *not* kept in an SSA register across iterations, unlike
   `stop` - reloaded/stored through its own global on every iteration
   instead (via two small factored-out helpers, `LoadVar`/`StoreIntoVar`,
   now also shared by `GenerateDesignatorValue`/`GenerateAssignStatement`),
   the same memory-backed model every other mutable module `VAR` already
   uses in this codegen - no SSA form for ordinary variables anywhere in
   this backend yet, FOR's own control variable included.

   EXIT branches to `Codegen.loopExitLabel`, a new field holding the
   *current innermost* LOOP's own exit-block label, saved and restored by
   `GenerateLoopStatement` around its own body - a LOOP nested inside
   another's body sets and restores its own, so an EXIT textually inside
   the inner one always targets the inner one. Confirmed directly against
   `Oberon2.pdf` 9.9/9.10 that this project's own front-end rule (already
   in place before this step; `SemanticActions.CheckExitStatement`) is
   correct, not just an assumption: "An exit statement... specifies
   termination of the enclosing loop statement" - the report's own prose
   literally names `LoopStatement` (LOOP), not WHILE/REPEAT/FOR, matching
   `loopDepth` already being incremented only by `CheckLoopStatement`.
   RETURN's own scope this step is just `ret void` for a bare RETURN -
   the only form `CheckReturnStatement` lets reach codegen at all today,
   since a module body (`procResultType = NIL`) is the only place with
   statement codegen until step 10 gives a function procedure a real
   result type to return a value for; the `s.value # NIL` arm is real
   code, not a stub, but genuinely unreachable until then - kept rather
   than omitted so this stays a total function instead of one silently
   relying on today's scope forever.

   Two real bugs were found and fixed this step, neither caught by
   `make build`/`make test` alone - both surfaced only by actually
   running this step's own new fixtures, the same "verify by running,
   not just by compiling" discipline steps 5/6 already established:

   - `Codegen.nextLabel` (the new basic-block label counter) was never
     initialized in `Generate*` - `cg.nextTemp := 0` was extended in
     place to `cg.nextTemp := 0; cg.nextLabel := 0`, but before that fix,
     every generated label number started from whatever garbage integer
     happened to be on the stack, producing IR that still happened to be
     *valid* (labels were still unique within a single run) but not
     *deterministic* across runs - caught by literally regenerating the
     same fixture's `.ll` twice and diffing, which would have silently
     broken every golden-file fixture this step adds the moment the
     compiler's own stack layout ever shifted.
   - The string-constant pre-pass from step 6 (`CollectStringConstantsStmt`)
     only ever walked `AssignStatementNode`/`CallStatementNode` - step
     6's own complete statement-kind set at the time it was written. Once
     this step added IF/CASE/WHILE/REPEAT/FOR/LOOP, a string-literal FFI
     argument nested inside any of their bodies (exactly what
     `llvm-control-flow`'s own fixture does throughout) produced a
     reference to a global this pre-pass never emitted, while real
     codegen (which *does* walk every nested body via
     `GenerateStatementSeq`) still generated a reference to it by name -
     caught by `clang` itself refusing to link ("use of undefined
     value"), not by any narrower earlier test. Fixed by extending
     `CollectStringConstantsStmt` to walk the exact same statement/
     expression shapes `GenerateStatement`'s own dispatch now does.

   Two new fixtures, matching this step's own two natural verification
   styles: `llvm-control-flow`, a compile+link+run+diff-stdout fixture
   (step 6's `SysWrite`-over-`write(2)` FFI, no `Console.Mod` needed)
   printing a one-letter marker for whichever IF/CASE/WHILE/REPEAT/FOR/
   LOOP branch or iteration actually ran; and `llvm-control-flow-ir`, a
   pure `-emit-llvm-ir` golden `.ll` diff (`llvm-straight-line-
   arithmetic`'s own style) whose computed final values were
   independently verified during development via the same C-harness
   linking technique step 5 established - `extern` declarations asm-
   renamed to each global's real, dotted LLVM name (e.g. `extern int16_t
   ctrl_ifResult __asm__("ctrl.ifResult");`, since "." is a valid
   unquoted LLVM identifier character but not a valid C one) - confirming
   `ifResult=2 caseResult1=20 caseResult2=1 caseResult3=99 whileSum=12
   repeatSum=10 forSum=30 loopCount=7` by hand, not by inspection of the
   IR alone. A genuine WITH-statement fixture was attempted and abandoned
   as currently impossible, not merely unwritten: `Oberon2.pdf` 9.11's
   own guard rule requires the tested variable to be "a variable
   parameter of record type or a pointer variable," and Phase 8 has
   neither VAR parameters (no procedure-with-body codegen until step 10)
   nor pointers (Phase 9) reachable from a module body yet - confirmed
   directly (`poc -check` rejects a plain record `VAR` guard with "a type
   guard requires a pointer designator"), so `GenerateStatement`'s own
   WITH fallback stays genuinely dead code for now, the same as RETURN's
   `s.value # NIL` arm, until Phase 9/10 make it reachable. All 102
   conformance tests pass (100 prior, two new).

8. **Fixed-size arrays and records.** Local/global storage, element/field
   access via `getelementptr`. No open arrays, no dynamic allocation.

   **Implemented.** "Local... storage" is still aspirational, same
   caveat every step before step 10 has had: no procedure-with-body
   codegen exists yet to own a local (`alloca`-backed) VAR, so this
   step's actual reachable scope, like every one before it, is
   module-level global VARs only - by design, though, nothing here is
   global-specific: `GenerateDesignatorAddress` (below) and the new
   `LoadAtAddress`/`StoreAtAddress` primitives it's built on take an
   arbitrary computed address, not a global name, so a local VAR gets
   this step's own array/record machinery for free the moment step 10
   adds one, no changes needed here.

   Element/field access lowers to one `getelementptr` per selector step
   - `r.arr[i].field` becomes three separate GEPs, not one fused multi-
   index GEP - simpler to generate and reason about, and this backend
   runs no optimization passes to care about the extra instructions
   either way, the same "straightforward over optimal" stance
   `GenerateDivMod`'s own unfused `select`-based correction already
   took back in step 5. `GenerateDesignatorAddress` walks a
   `Designator`'s own selector chain generally (any mix of
   `FieldSelector`/`IndexSelector` in any order/depth), returning
   `FALSE` the moment it meets a shape needing a capability this
   backend doesn't have: a `PointerType` anywhere along the chain
   (`CheckDesignator` auto-dereferences one for *both* `.` and `[`, so
   a plain array/record VAR's own selector chain can still legitimately
   lead into one), a `DereferenceSelector`/`GuardSelector`, a
   `FieldSelector` resolving to a type-bound method instead of a data
   field, or - a real bug found and fixed during this step's own
   testing - a `FieldSelector` into a record *with* a base type
   (extension): `LLVMTypes.RecordTypeString` already refuses to
   describe an extended record's layout at all (the literal text
   `"<unsupported>"`, not a real LLVM type, unchanged since step 4),
   but `GenerateDesignatorAddress` didn't originally re-check that
   before emitting a GEP against whichever record type `Types.FindField`
   happened to resolve the field in - producing a GEP whose own pointee-
   type operand was the bare, ill-formed text `<unsupported>`, caught by
   a scratch `RECORD (Base) ... END` fixture during development, not by
   any golden-file diff (nothing existing exercised record extension at
   all). Fixed by refusing any `FieldSelector` whose record has a
   non-`NIL` `baseType`, mirroring `RecordTypeString`'s own check
   exactly, before it ever reaches `EmitGEP`. A struct GEP's own index
   is always `i32` (an LLVM `getelementptr` requirement specific to
   struct indices, confirmed against the LLVM Language Reference, not
   assumed) and is the field's 0-based position among `rec.fields`
   (declaration order - the same order `RecordTypeString` already used
   to build the struct literal, so a field's position there is exactly
   its struct index); an array GEP's own index reuses the index
   expression's own already-computed value/type unchanged (LLVM
   tolerates any integer width for an array index, so no widening is
   needed there), and naturally composes across a multi-dimensional
   `a[i,j]`-style chained index list or a genuinely nested `ARRAY OF
   ARRAY` by re-checking `IS Types.ArrayType` on the newly-descended
   element type at each step.

   Whole-value `ARRAY`/`RECORD` assignment (`v2 := v`, `p2 := p`, same
   declared type on both sides - the only shape Appendix A's own
   assignment-compatibility rules ever allow here, since Phase 8 has no
   RECORD extension in its backend's own reachable scope for a
   projection-style partial copy to even apply) needed **no new codegen
   at all**: `LoadVar`/`StoreIntoVar` (step 7) were already fully
   generic over `LLVMTypes.TypeString`'s own output, and LLVM's `load`/
   `store` instructions already support an aggregate (`[N x T]`/
   `{ T1, T2, ... }`) type directly, by value, same as any scalar -
   confirmed, not assumed, by generating IR for a scratch fixture before
   writing a single line of new code for it. `LoadVar`/`StoreIntoVar`
   themselves became thin wrappers over the two new, genuinely primitive
   `LoadAtAddress`/`StoreAtAddress` procedures (keyed on an address+type
   pair, not a `SymbolTable.Object`) - `GenerateDesignatorValue`'s own
   selector-chain read path reuses `LoadAtAddress` directly on whatever
   address `GenerateDesignatorAddress` computes, and `GenerateAssign-
   Statement`'s selector-chain write path reuses `StoreAtAddress` the
   same way, so a selector-chain assignment target/expression is treated
   identically to a bare one once its own address is known.

   Deliberately left open, not attempted: extending the step 6 FFI's
   `ARRAY OF CHAR` value-argument handling (`GenerateStringArgValue`) to
   accept a general fixed-`CHAR`-array-typed designator (e.g. a record
   field or array element holding text) rather than only a literal
   string constant - real, in-scope-adjacent Oberon-2, but not this
   step's own stated scope ("element/field access via `getelementptr`"),
   and broadening it would have blurred step 8's own boundary rather
   than sharpened it; still cited as future work by
   `GenerateStringArgValue`'s own header comment, unchanged. Likewise
   left open: a *bare* (non-selector) `VAR` of `POINTER`/extended-
   `RECORD` type already reaches `LoadVar`/`StoreIntoVar` with the same
   literal `"<unsupported>"` type text this step's own record-extension
   bug hit - but that gap predates this step entirely (any bare
   assignment to such a VAR was already reachable, unchanged, since step
   5, well before selectors existed) and is orthogonal to what this step
   actually added, so it's documented here rather than silently carried
   forward or fixed as a drive-by.

   Two new fixtures, matching step 7's own two-fixture pattern:
   `llvm-arrays-records` (compile+link+run+diff-stdout, branching on a
   computed array/record result to print one of two literal markers per
   check - step 6's FFI still can't print a computed `ARRAY OF CHAR`
   value directly, per the deliberately-left-open gap above) and
   `llvm-arrays-records-ir` (a pure `-emit-llvm-ir` golden `.ll` diff
   covering a 1D array, a 2D array via the `ARRAY m, n OF T` comma
   sugar, a plain record, a record nested inside another record, and an
   array of records - whole-value assignment of both an array and a
   record, and every read/write combination `GenerateDesignatorAddress`
   needs to compose correctly - independently verified during
   development via the same C-harness linking technique step 5/7 already
   established: `sum=312`, confirmed by hand). All 104 conformance tests
   pass (102 prior, two new).

9. **Runtime traps.** Index-range checks and CASE-without-matching-label,
   using a `write(2)`/`exit(2)` abort path declared directly by the
   backend itself, the same direct-FFI style step 6's own `SysWrite`
   fixtures already used (there is no separate `Runtime.Mod`/
   `Console.Mod` module yet — see step 6's own retrospective, "no
   `Console.Mod` needed"). Match voc's actual, source-verified flag
   posture, not `AGENTS.md`'s own paraphrase: voc's `OPM.Mod`/`OPV.Mod`
   show `-x`/`inxchk` (index-range check) is ON by default and is the
   flag that actually governs array-index bounds checking
   (`OPV.Mod:300`); `-r`/`ranchk`, OFF by default, governs a different,
   narrowing-conversion-style check (`OPV.Mod:246`, plus `CHR()` bounds)
   that is out of this step's scope. CASE-without-matching-label
   (`__CASECHK`, `OPV.Mod:717`) has no gating flag at all — voc emits it
   unconditionally whenever a CASE has no ELSE branch. NIL-dereference
   trapping (`-p`) doesn't apply yet since there are no pointers in
   scope.

   **Implemented 2026-09-18.** Two traps, both lowering to a shared
   `EmitTrap` abort sequence (`LLVMCodeGenerator.Mod`): print a fixed
   diagnostic string to stderr (fd 2, keeping trap output cleanly
   separable from a fixture's own stdout markers), `exit()` with a
   dedicated per-trap code (2 for index-range, 3 for CASE — this
   backend's own convention; no voc runtime source was available on
   this machine to match against), then `unreachable` — a real LLVM
   terminator, so the caller's own next `EmitLabel` still lands
   somewhere syntactically valid, preserving the "always leave an open
   block" invariant step 7 established, the same way RETURN/EXIT's own
   dead-block-after-terminator already does.

   The index-range check (`EmitIndexRangeCheck`) is one `icmp sge`/
   `icmp slt`/`and`/`br i1` sequence per `IndexSelector` step, inserted
   into `GenerateDesignatorAddress` immediately before the `EmitGEP` it
   already emits there — `arr.length` is always a compile-time-known
   constant, so no dynamic length lookup is needed. The CASE trap fires
   from `GenerateCaseStatement` when no label matched and there is no
   ELSE branch.

   Two real design problems surfaced during this step, neither of which
   was visible until actually building it:

   - **Duplicate-`declare` collision.** `write`/`exit` need declaring
     once for the trap's own abort path to call, but several existing
     fixtures (`llvm-hello-world`, `llvm-control-flow`,
     `llvm-arrays-records`) already declare an external `PROCEDURE ["C",
     "write"] SysWrite(...)` mapping to the same C symbol "write" -
     confirmed empirically that `clang`/LLVM rejects two `declare` lines
     for the same symbol outright (`error: invalid redefinition of
     function 'write'`), even with identical signatures. Fixed by
     `HasExternalNamed`, which scans the module's own FFI declarations
     first; `EmitRuntimeSupport` only emits its own `declare` for
     `write`/`exit` when the user's module hasn't already declared one
     under that same C name. This is a real, narrow, documented
     limitation, not airtight in general (a fixture that declared
     `write`/`exit` with an incompatible signature of its own would
     produce a type-mismatched call - `EmitTrap` always calls with a
     fixed i32/ptr/i64 shape, it doesn't dynamically re-derive one from
     whichever declaration is actually in scope), but every fixture this
     project has written declares a compatible shape already, and this
     matches the same fixed, x86_64-only ABI caveat step 6's own
     `SysWrite` fixtures already accept.

   - **`elseBody = NIL` is ambiguous.** `GenerateCaseStatement` needs to
     distinguish "no ELSE clause at all" (must trap on an unmatched
     value, matching voc's own unconditional `__CASECHK`) from an
     explicit-but-empty `ELSE END` (must do nothing - legal Oberon-2, no
     trap). Both parse to `s.elseBody = NIL`:
     `Parser.ParseStatementSeq` returns `NIL` for a zero-statement
     sequence regardless of whether the `ELSE` keyword was present at
     all. This is a real, previously-latent gap in `SyntaxTree`'s own
     `CaseStatementNodeDesc` (not something step 9 could route around
     locally) - fixed by adding a `hasElse: BOOLEAN` field, set by
     `Parser.Mod`'s own case-statement parsing based on whether it
     actually consumed the `ELSE` token (not by inspecting the parsed
     body), threaded through `SemanticActions.NewCaseStatement`.
     `GenerateCaseStatement` now branches on `s.hasElse`, not
     `s.elseBody # NIL`. IF doesn't need the same fix: an IF with no
     ELSE and an IF with an empty ELSE are genuinely the same statement
     ("do nothing" either way), with no trap semantics to distinguish
     them.

   Two fixtures, both compile+link+run, each deliberately triggering
   exactly one trap (a module can only ever observe *one* trap firing
   per run, since `exit()` ends the process - there's no argv/stdin
   input mechanism yet to pick a code path at run time, so "both traps
   in one fixture" isn't possible): `llvm-index-range-trap` indexes an
   array one past its bound (via a VAR read-back, not a literal, so the
   out-of-range index survives semantic checking and the trap actually
   fires at run time) and `llvm-case-trap` runs a non-exhaustive,
   ELSE-less CASE against a value matching neither label. Neither
   fixture reuses `testenv.sh`'s own `poc_build_run` helper - both need
   the built program's exit status and stderr output, which
   `poc_build_run`'s stdout-only plumbing doesn't capture; each `test.sh`
   redirects the program's stderr into the same "result" stream as
   stdout (`2>&1`) and appends `exit=$?`, relying on both `write(2)`
   targets being unbuffered raw syscalls in a single-threaded program,
   so their combined byte order is exactly execution order. Each
   fixture's own `expected` confirms all three things at once: the
   marker printed just before the trigger appears (the check point was
   reached), the marker after it does *not* (the trap's own
   `write`/`exit`/`unreachable` sequence really does stop the program),
   and the exit status matches the trap's own documented code.

   `llvm-arrays-records-ir`'s own golden `.ll` (already exercising
   several array-index accesses) needed regenerating to include the new
   range-check instructions before each GEP - inspected by hand before
   accepting: every check compares a compile-time-constant index
   against the correct declared array length. `llvm-straight-line-
   arithmetic`, `llvm-emit-ir`, and `llvm-control-flow-ir`'s own goldens
   also needed regenerating, purely for `EmitRuntimeSupport`'s new
   unconditional `write`/`exit` declares and the two trap-message
   globals appearing in every module now, the same "unconditional for
   every module, harmless if unused" stance `EmitExternalDeclares`
   already established for user-declared externals - none of those
   three fixtures' own generated code changed. All 106 conformance tests
   pass (104 prior + 2 new).

10. **Ordinary procedure calls.** User-defined (non-external,
    non-type-bound) `PROCEDURE` declarations: parameter passing (value vs.
    `VAR`), local storage, `RETURN`.

    **Implemented 2026-09-18.** A real architectural gap surfaced before
    any codegen could be written: a procedure body's own params/locals
    scope (`SemanticActions.CheckProcedureBody`'s `bodyScope`) is opened
    and discarded entirely within one checking-time call frame, never
    persisted anywhere the backend could find it again, and
    `SyntaxTree.Mod` is a deliberately import-free "pure data" leaf
    module (its own header comment) - no resolved `Types.Type`,
    `SymbolTable.Scope`, or anything else from the front end's own
    resolution passes can ever be stashed directly on a `SyntaxTree`
    node, so a field like `ProcDeclNode.bodyScope` was never an option.
    Fixed by extracting the scope-opening half of `CheckProcedureBody`
    (receiver/formals/local-VAR resolution, not the nested-procedure or
    statement checking) into a newly-exported
    `SemanticActions.OpenProcedureBodyScope*`, callable a second time,
    safely: by the time codegen runs, the module already passed
    `CheckModule` with zero diagnostics, so re-deriving the identical
    scope from the identical AST a second time just rebuilds an
    equivalent result, not new errors. `LLVMCodeGenerator.Mod` now
    imports `SemanticActions` (no cycle - `SemanticActions.Mod` has no
    reach into the backend at all) and calls this once per procedure.

    Local/parameter *storage* needed a second real extension: every VAR
    codegen since step 5 addressed a `SymbolTable.Object` by building
    "@Module.name" unconditionally (`LoadVar`/`StoreIntoVar`/
    `GenerateDesignatorAddress`'s own base-object resolution, each
    independently), which is simply wrong for a local, alloca'd
    variable. Fixed by centralizing all three into one new
    `ResolveVarAddress`, backed by a small `LocalBinding` side table on
    `Codegen` (SymbolTable's own `ObjectDesc` is deliberately semantics-
    free - its own header comment - so it carries no field to hang a
    backend address on): a local hit resolves to its own alloca'd
    address; a miss falls back to the "@Module.name" convention every
    module-level VAR still uses. This is exactly what step 8's own
    retrospective anticipated when it built `LoadAtAddress`/
    `StoreAtAddress` as the genuinely primitive address+type operations
    ("a local ... VAR gets the identical machinery for free ... nothing
    here is hardcoded to 'global'") - true this time with no changes
    needed to either of them.

    A VAR parameter's own incoming LLVM argument *is* the address
    already (always `ptr`, `ParamLLVMType`'s own existing convention) -
    bound directly into `LocalBinding`, no alloca. A value parameter
    gets a fresh alloca'd slot with the incoming argument stored into it
    immediately; a local VAR gets an alloca left deliberately
    uninitialized (real Oberon-2 gives a local no defined initial value,
    unlike a module-level VAR's own `zeroinitializer`). `GenerateVarArg-
    Value` - previously hand-rolling its own "bare module VAR only"
    address logic - now just delegates to `GenerateDesignatorAddress`
    directly: a VAR argument reached through a record field or an array
    index (`Increment(p.x, 1)`, `Increment(v[1], 5)`) now works for
    free, through the identical address computation (and, for an array
    index, the identical step 9 range check) an assignment target
    already uses - not a new, narrower capability, a deleted limitation.

    `RETURN`'s own codegen (step 7) only ever emitted `ret void`,
    correctly, because nothing before this step could reach the
    `s.value # NIL` arm at all (module-level code can't RETURN a value).
    Now gated on a new `Codegen.currentProcResultType` (NIL at module
    level and inside a proper procedure) rather than `s.value`'s own
    NIL-ness alone, because `SemanticActions.CheckReturnStatement` only
    ever diagnoses a value where none is allowed, never the reverse - a
    bare `RETURN` inside a function procedure is real, front-end-
    accepted Oberon-2, and so is a function procedure whose body falls
    off the end with no `RETURN` on some path at all (`CheckProcedureBody`'s
    own "must return a value" check is deliberately shallow, not full
    reachability analysis - its own header comment). Both cases now
    lower to the same well-typed placeholder `Unsupported` already
    established for out-of-scope constructs (`ret <type> 0`/`0.0`) -
    verified in this step's own `MaybeReturn` fixture procedure, whose
    `n <= 0` path takes exactly this fallback.

    Call-site codegen needed almost nothing new: `GenerateCallArgList`/
    `EvaluateCallArg`/`ParamLLVMType` (steps 6/8) were already fully
    generic over `Types.Param`/`Types.ProcedureType`, so the new
    `GenerateOrdinaryCall` is a near-verbatim copy of `GenerateExternal-
    Call`, targeting `@Module.procName` (a new shared `ModuleQualified-
    Name` helper, also now used by `ResolveVarAddress`'s own global
    fallback) instead of an external's own C symbol name. Recursive
    calls (`Fact` calling itself) needed no special handling at all - by
    the time any procedure's own body is generated, every procedure in
    the module (regardless of textual order) is already a fully-
    resolved `procClass` Object in the module's own top-level scope
    (built by `CheckModule`, a complete, earlier pass), reachable via
    ordinary scope-chain lookup from a body's own `bodyScope`.

    `Generate*`'s own driver gained a genuine gap that had to be fixed
    before testing could even start: the string-constant pre-pass
    (`CollectStringConstantsSeq`) only ever walked `module.statements`
    (the module's own top-level body) - once a procedure body could
    itself contain a string-literal FFI argument, that string's global
    was never emitted while real codegen still referenced it. Fixed by
     walking every ordinary procedure's own body through the identical
    pre-pass too, before any `define` is emitted (module-level globals/
    declares/string-constants, in the same order step 9 already
    established, now come first; each procedure's own `define` next;
    `_init`/`main` unchanged, last).

    Open-array value/VAR parameters (`s: ARRAY OF CHAR` used as more
    than an opaque FFI `ptr`, needing a real length/dope-vector
    convention to be usable via `LEN` or indexing) are a known, narrow,
    *not* exercised gap - `ParamLLVMType`'s existing "ptr" convention
    for one produces syntactically valid but semantically incomplete IR
    if such a parameter were ever read from, not attempted here; no
    fixture needs it, and nothing else in Phase 8's own scope
    (`PredeclaredProcedures` lowering, step 11) forces the question yet.
    (Built in Phase 9 step 7.)

    Two fixtures, matching steps 7/8/9's own dual-verification pattern:
    `llvm-procedures`, a compile+link+run+diff-stdout fixture (value/VAR
    params, local storage, recursion via `Fact`, a VAR argument through
    a record-field and an array-index selector, and `MaybeReturn`'s own
    deliberate fall-off-the-end path) branching on a computed result to
    print one of two literal markers; and `llvm-procedures-ir`, a pure
    `-emit-llvm-ir` golden `.ll` diff exercising the same constructs
    (minus the fall-off-the-end case, which has no defined value to
    check), independently verified via the same C-harness linking
    technique steps 5/7/8 already established - `total=137 p.x=2 v[1]=5`
    confirmed by hand, not by inspection of the IR alone. IR determinism
    (regenerating the same fixture twice and diffing) was re-checked by
    hand given this step's much larger surface area - clean, no repeat
    of step 7's own uninitialized-counter bug. All 108 conformance tests
    pass (106 prior + 2 new).

11. **Predeclared-procedure lowering.** The in-scope §10.3 subset listed
    above, each getting its own lowering in `LLVMCodeGenerator.Mod` per
    `PredeclaredProcedures.Mod`'s existing header-comment split
    ("semantic checking lives in the front end, lowering lives in the
    backend").

    **Implemented 2026-09-18.** `ABS`, `ODD`, `CHR`, `ORD`, `CAP`, `LEN`
    (both the one- and two-argument forms), `INC`/`DEC` (both the
    default-`+1`/`-1` and explicit-amount forms), `COPY`, and `HALT` -
    `NEW`/`DISPOSE`/`SYSTEM.*` stay out of scope (Phase 9, they
    presuppose `POINTER`). Dispatch reuses the front end's own marker:
    `SymbolTable.Find` already resolves a bare name to a `procClass`
    Object whose `.type = Types.PredeclaredProcedureType`
    (`SymbolTable.Mod`'s module body inserts all 20 predeclared names
    into `Universe` this way), so `GenerateCall` just checks that marker
    *before* its existing external/ordinary `procClass` checks (a
    predeclared procedure is neither) and routes to a new
    `GeneratePredeclaredCall`, a string-comparison dispatcher over the
    10 in-scope names.

    Every one of the 10 reuses existing primitives rather than inventing
    new machinery - `EmitBinOp`/`EmitSelect`/`EmitConvert` for the
    arithmetic-shaped ones, `GenerateDesignatorAddress`/`LoadAtAddress`/
    `StoreAtAddress` for anything reading or writing a variable,
    `EmitGEP` for `COPY`'s own byte-by-byte unrolled store sequence,
    `ConstantEvaluator.Evaluate` for `HALT`'s compile-time constant. The
    one genuinely new question each answered was *width*: several
    operations (`ORD(CHAR)`'s `zext`, `ORD(SET)`'s `trunc`, `CHR`/`ODD`'s
    `trunc`-or-no-op) turn out to be unconditionally correct across both
    `-O2`/`-OC` size models without any runtime branching on width, once
    `LLVMTypes.BasicTypeString`'s own width table is checked directly:
    `CHAR` is always `i8` in both models, and `Integer`'s width is always
    strictly less than `Set`'s in both models, so the direction of the
    conversion never depends on which model is active. `ORD` additionally
    special-cases a single-char STRING literal argument directly against
    the `SyntaxTree.LiteralExprNode` shape (bypassing `GenerateExpr`
    entirely, the same way `GenerateStringArgValue` already treats a
    string literal as never a loadable "value" elsewhere in this
    backend) - `CAP`, unlike `ORD`, has no such exception
    (`PredeclaredProcedures.CheckCap`'s own check requires a bare `CHAR`),
    so `CAP` only ever sees a loaded `CHAR` value. `COPY` only lowers a
    literal-string-source/plain-designator-CHAR-array-destination shape,
    unrolling a fixed `EmitGEP`+`store i8` sequence (source length known
    at compile time, destination clamped to the array's own declared
    length) rather than a runtime loop - no fixture needs more. `HALT`
    reuses `@exit`, already unconditionally declared by step 9's
    `EmitRuntimeSupport` for the two traps, followed by `unreachable` and
    step 9's own dead-block-after-terminator pattern.

    A real, pre-existing bug (not in any of the 10 procedures above, but
    surfaced while testing them) was found and fixed:
    `GenerateStringArgValue`/`GenerateVarArgValue`'s own fallback for an
    out-of-scope string/VAR call argument used to embed its
    `"; unsupported: ..."` diagnostic *directly inside `result.text`*,
    unlike the shared `Unsupported` procedure itself, which always writes
    its diagnostic as its own separate comment line and returns a clean
    placeholder value. Since a call argument's `.text` gets spliced
    mid-line into a `"call ...("` argument list by `GenerateCallArgList`,
    the embedded comment corrupted the IR - a `;` mid-argument-list
    comments out everything after it on the line, including the closing
    `)`, and `clang` correctly rejected the result with `expected ','
    in argument list`. This had been latent since string/VAR call
    arguments were first introduced (step 6/8): every fixture before now
    happened to only pass literal strings/bare VARs to external calls,
    never a shape that reached either fallback branch from inside a call
    argument position. It surfaced once a scratch test forwarded a
    procedure's own `ARRAY OF CHAR` value parameter into another call's
    `ARRAY OF CHAR` argument - a real, still out-of-scope shape (open
    arrays remain step 10's own documented gap), but the *fallback
    text itself* being malformed was an independent, worth-fixing bug.
    Fixed by giving `GenerateStringArgValue` a `VAR w: Files.Rider`
    parameter (matching `GenerateVarArgValue`'s existing signature) and
    having both write their diagnostic as a standalone line via
    `WriteStr`/`WriteLn` before returning a bare `"null"` as `result.text`
    - exactly `Unsupported`'s own established pattern, just not
    previously applied here.

    Two more pre-existing, unrelated-to-this-step gaps were hit (and
    routed around, not fixed) while designing this step's own fixtures:
    a single-char STRING literal used as a plain `CHAR` value *outside*
    a call argument or `ORD`'s own special-cased position (e.g. `CHAR
    variable := "q"`, or `<CHAR value> = "A"` in a general comparison)
    has no general lowering in `GenerateExpr` at all - only `ORD`'s own
    codegen intercepts that one literal shape directly - so both
    fixtures use hex `CHAR` literals (`nnX`) instead, everywhere except
    `ORD`'s own argument (kept as `ORD("Z")`, still exercising that
    dedicated path). And forwarding an `ARRAY OF CHAR` *value parameter*
    into another call (the shape that originally surfaced the bug above)
    stays unexercised in the real fixtures for the same reason step 10's
    own retrospective already gives it a pass: open arrays are a known,
    narrow, not-yet-built convention, out of this step's own scope.
    (Exercised for real by Phase 9 step 7's `llvm-open-array-params`.)

    Three fixtures: `llvm-predeclared`, a compile+link+run+diff-stdout
    fixture covering the 9 non-`HALT` procedures (`HALT` terminates the
    process, incompatible with an "OK"/"FAIL" trailing write) including
    both `LEN` forms via a 2-D array (`dim0`/`dim1`); `llvm-predeclared-
    halt`, HALT's own dedicated exit-status fixture (matching
    `llvm-index-range-trap`'s own "capture stdout + exit status, not
    `poc_build_run`" pattern) confirming `HALT(3)` prints exactly
    `"before"`, exits `3`, and never reaches the statement after it; and
    `llvm-predeclared-ir`, a pure `-emit-llvm-ir` golden `.ll` diff over
    the same 9 non-`HALT` procedures, independently verified via the same
    C-harness linking technique steps 5/7/8/10 already established
    (`absVal=7 oddVal=1 chrVal=65 ordVal=90 capVal=81 lenVal=5 dim0=3
    dim1=4 i=10 s="hi"` confirmed by hand). IR determinism re-checked by
    hand (regenerate twice, diff both the driver message and the `.ll` -
    clean). All 111 conformance tests pass (108 prior + 3 new).

12. **General multi-module user programs + program entry.** Extend the
    driver to transitively discover and compile every user-authored
    `IMPORT` (via `ModuleInterface.Mod`'s already-resolved import graph),
    not just the fixed rtl set from step 6. Generate a native `main` that
    calls each imported module's init function in import-dependency
    order, then the top (command-line-specified) module's own
    `BEGIN...END` sequence — the same ordering `Oberon2.pdf` §11
    prescribes for module initialization generally.

    **Implemented 2026-09-18.** Two genuinely separate problems turned out
    to be bundled under this one step's own heading, discovered in order
    by trying to write the first real multi-module fixture: qualified-
    reference codegen (`Module.Name`) had never been built at all -
    `GenerateDesignatorAddress`/`GenerateDesignatorValue`/`GenerateCall`/
    `GenerateAssignStatement` each already had their own explicit
    `d.qualifier[0] # 0X` bailout, every one hand-labeled "PLAN.md Phase 8
    step 12+" back when it was written - and the existing `.sym`-based
    `IMPORT` resolution (`SemanticActions.ResolveImport`) only ever reads
    an imported module's *interface*, with no procedure bodies or
    statement sequences to generate real code from at all, so a second,
    independent "read and check the module's own real `.mod` source"
    pass was needed before any of that qualified-reference codegen had
    anything to target.

    **Qualified-reference codegen.** `SymbolTable.ObjectDesc` already
    carried everything needed - a `moduleClass` Object's own
    `moduleScope`/`realModuleName` fields (present since Phase 7, for
    `ModuleInterface.Mod`'s own `.sym`-reprinting needs) are exactly
    "the imported module's exported scope" and "its real name, distinct
    from whatever local alias this module imported it under" - so no
    front-end changes were needed, just a new `ResolveQualifiedObject`
    (mirroring `SemanticActions.FindQualified`'s own private logic,
    small enough to duplicate rather than export, the same call
    `StringConstName`'s own precedent already made) that resolves a
    designator's base name, qualified or not, and returns *both* its
    `SymbolTable.Object` and its home module's own real name. A second
    new helper, `QualifiedName` (an explicit-home-module sibling of the
    existing `ModuleQualifiedName`, which stays exactly as it was for
    every one of its existing, still-only-ever-unqualified call sites),
    builds the correct `"@realModuleName.name"` LLVM symbol from that -
    critically *not* `cg.moduleName` (the module currently being
    compiled), which is what every symbol-building call site used
    unconditionally before this step, harmlessly until a qualified
    reference could name something declared somewhere else. Every one of
    the four bailouts became real codegen by threading `homeModule`
    through to whichever of `ResolveVarAddress`/`StoreIntoVar`/
    `GenerateOrdinaryCall` it needed (a qualified VAR can never be a
    local binding - `cg.locals` only ever holds the *current* procedure's
    own alloca'd params/locals - so the qualified path skips
    `ResolveVarAddress`'s own local-binding check entirely and calls
    `QualifiedName` directly, a small but real asymmetry from the
    unqualified path worth calling out explicitly in each of the three
    call sites' own comments).

    **Whole-program discovery.** A new `ModuleInterface.ReadModuleSource*`
    (mirrors `ReadSource*` exactly, reading `"<name>.mod"` instead of
    `"<name>.sym"` via the identical cwd-then-search-path `Open`) gives
    Poc.Mod's new `DiscoverModule` a way to find each imported module's
    own real source. `DiscoverModule` is a straightforward post-order
    recursive descent over `SyntaxTree.ModuleNode.imports` - recurse into
    a module's own imports first, append itself to the accumulated list
    only afterward - which is exactly topological order for a DAG
    (imports before importers), matching `Oberon2.pdf` §11 directly, and
    skips a module already present in the list (a diamond import - two
    independent modules both importing a shared third one - must not be
    compiled or linked twice, confirmed against a real diamond-shaped
    scratch program: the shared module's own init ran exactly once,
    visible in `main`'s own generated call sequence). Real import cycles
    can't reach this walk at all: it only ever runs after the top
    module's own `.sym`-based `CheckModule` has already succeeded, and
    `SemanticActions.ResolveImport`'s own `ImportChain` already rejects
    any cycle during that pass - so no separate "currently being
    visited" guard was needed on top of the diamond-dedup check.
    `Diagnostics.fileName`/`errorCount` are saved/restored and
    snapshotted around each recursive call, mirroring `ResolveImport`'s
    own established reasoning exactly (a plain `Reset*` would wrongly
    wipe out errors from an unrelated, already-completed part of the
    same compilation).

    **One link unit, several modules.** `LLVMCodeGenerator.Generate*`
    (single-module) is gone, replaced by `GenerateProgram*`, taking a new
    exported `ModuleList` (module+scope pairs, in the dependency order
    `DiscoverModule` already produced) instead of one module/scope pair -
    its only caller, `LLVMToolchainDriver.EmitIR*`/`Build*`, is updated
    to match, and Poc.Mod always builds a `ModuleList` now (a one-element
    list for the ordinary, no-real-`IMPORT`s case every fixture before
    this step is). For a one-element list `GenerateProgram*` produces
    byte-identical IR to the old `Generate*` - confirmed against every
    pre-step-12 golden-file fixture unchanged, one (`llvm-predeclared-ir`)
    needing its own golden file regenerated for a real, deliberate
    reason given below, not a regression. Compiling more than one module
    into a single link unit surfaced two latent bugs that a single-module
    program could never have hit:
      - `EmitRuntimeSupport`'s own `write`/`exit` "declare" lines and its
        two trap-message globals used to be emitted once *per module*
        (guarded only against that same module's own FFI declarations
        already covering the same C symbol - step 9's own retrospective
        already documents `clang` rejecting two "declare"s of the same
        symbol outright). Two modules in the same program, each
        possibly declaring "write" externally under their own Oberon
        name, would have collided. Fixed by a new whole-program
        `Codegen.declaredExternals` set (never reset between modules,
        unlike `locals`/`currentProcResultType`), checked/updated by
        `EmitExternalDeclares` for every module before `EmitRuntimeSupport`
        (now called exactly once, no longer taking a `module` parameter
        at all) checks the same set for `write`/`exit`.
      - `StringConstName`'s own global names were derived from a string
        literal's source line/column alone - unique *within* one
        module's own file, not across a whole program: two modules each
        happening to have a string literal at the same line/column would
        have collided on the identical global name. Fixed by folding
        `cg.moduleName` into the name too (`"@.str.<Module>.L<line>.
        C<col>"`) - the one change that regenerated `llvm-predeclared-
        ir`'s own golden file above, its only two string constants now
        correctly reading `@.str.predeclaredir.L24.C17`/`...L34.C8`
        instead of the old, module-less `@.str.L24.C17`/`...L34.C8`.

    Neither gap could have been found by any fixture before this step -
    every one of them compiled exactly one module, where "once per
    module" and "once per program" are the same thing.

    A third, purely mechanical bug cost real time during this step's own
    development, worth recording since it will recur: writing an
    Oberon-2 comment that names an *exported* identifier immediately
    followed by a closing parenthesis - `"...see GenerateProgram*)."` -
    accidentally spells the token that closes a `(* ... *)` comment
    early (the export marker `*` plus the parenthesis together read as
    `*)`), silently truncating the comment and leaving its own remaining
    text as bare, malformed source. Both instances this step introduced
    were caught immediately by `make build` itself (a real `END missing`
    parse error, not a silent miscompile), fixed by rewording rather than
    ever writing `Name*)` adjacently again.

    One real fixture, `llvm-multi-module` (compile+link+run+diff-stdout,
    matching `test/conformance/module-cross-import`'s own two-`.mod`-file
    layout but promoted to real codegen rather than semantic-check-only):
    a library module (`lib.mod`) exporting a VAR and two ordinary
    procedures, and a client module (`client.mod`) importing it under a
    *different* alias (`IMPORT Lib := lib`) specifically to prove every
    generated symbol comes out `"@lib.*"`, never `"@Lib.*"` or
    `"@client.*"` - exercising a qualified call with a result
    (`Lib.Add`), a qualified call used as a statement (`Lib.Accumulate`),
    and a qualified VAR used as both a read and an assignment target in
    the same statement (`Lib.total := Lib.total + 1`). `test.sh` first
    runs `-emit-interface` on `lib.mod` (still needed for client.mod's
    own ordinary `.sym`-based type checking, unchanged by this step) before
    `poc_build_run`'s own `-build client.mod`, which now transitively
    discovers and compiles `lib.mod`'s real source on its own. IR
    determinism (regenerate twice, diff) and the diamond-import scratch
    program mentioned above were both verified by hand rather than
    turned into their own fixtures, matching this step's own "prove the
    driver-level mechanism once, thoroughly, rather than one fixture per
    behavior" scope. All 112 conformance tests pass (111 prior + 1 new).

13. **Fixture promotion + portability verification.** Promote a subset of
    earlier type-check-only fixtures to compile+link+run+diff;
    cross-check output against `voc` compiling the same source where
    practical. Run the same fixtures on Linux and on at least one BSD
    (ideally all three of NetBSD/OpenBSD/FreeBSD) — a distinct `clang`
    target triple per OS from step 2's `-target` flag, so this must be
    verified by actually running there, not assumed from POSIX
    compatibility alone.

    **Implemented 2026-09-18.** Two genuinely separate halves, taken in
    the order the step's own heading lists them.

    **Portability verification found a real, previously-deferred bug.**
    No BSD host was available locally (no VM/container can run a real
    BSD kernel on this machine - Docker shares the Linux host kernel).
    Asked the user directly rather than skipping or assuming; given real
    SSH access to two machines - `erekose` (OpenBSD 7.9, i386) and
    `terhali` (NetBSD 11.0, amd64) - covering two of the three OSes this
    step names, both a 32-bit and a 64-bit target. Compared real
    `clang -S -emit-llvm` output on an empty C program across Linux
    x86_64, NetBSD x86_64, and OpenBSD i386: NetBSD's datalayout string
    is byte-identical to Linux's, but OpenBSD's is genuinely different
    (explicit `p:32:32` pointer-size spelling, different f64/f80
    alignment, no `:64` in the natural-widths list) - confirming
    `hostDataLayout`, the single hardcoded x86_64-Linux string step 2's
    own stub introduced and explicitly flagged as "not this step's job
    either," was silently wrong for any 32-bit target. Fixed by
    replacing it with two constants, `dataLayoutW64`/`dataLayoutW32`,
    selected in `GenerateProgram*` by `ConstantEvaluator.wordSize` -
    already set correctly from the same `-target` triple by `Poc.Mod`'s
    own `SetWordSizeFromTriple` before codegen starts, so no new
    triple-parsing logic was needed. Deliberately scoped to only the two
    triples actually verified on real hardware, not a full
    per-architecture table: `LLVMTypes.WordSizeForTriple*` recognizes
    other architecture names for word-size purposes only, and nothing in
    Phase 8 has built or verified codegen for one. `make test` (112,
    unchanged) confirmed zero regressions - every existing fixture is
    x86_64, so exercises only the unchanged `dataLayoutW64` path.

    Verified end-to-end, not just by inspecting `.ll` text: all 9
    existing LLVM runtime fixtures (`llvm-hello-world` through
    `llvm-multi-module`) were cross-compiled locally with the correct
    `-target` triple, copied to each real machine, and built+run there
    with that machine's own native `clang` - `i386-unknown-openbsd7.9`
    on erekose, `x86_64-unknown-netbsd10.0` on terhali (multi-module
    needed its own `-emit-interface` pre-step on each host first, same
    as locally). All 18 runs (9 fixtures × 2 hosts) produced the exact
    expected stdout and exit code, including the trap/HALT fixtures'
    exit-code checks. One test-harness mistake of this session's own
    making was caught and fixed along the way, worth recording since it
    recurred: an `ssh host 'prog; echo; echo EXIT=$?'`-style invocation
    captures the intervening bare `echo`'s own (always-zero) exit
    status, not the program's - the exact same mistake this session had
    already made once locally testing HALT. Fixed by capturing
    `ec=$?` as its own statement immediately after the program runs,
    before any other command. All generated artifacts (`.ll`s,
    executables, `/tmp/empty.c`) were removed from both remote hosts and
    locally afterward; this ad hoc scp/ssh sweep was not turned into
    durable tooling or a script in the repository, since it needs real
    external hosts to mean anything and can't run as part of `make
    test`.

    **Fixture promotion found voc genuinely can't cross-check most of
    Phase 8's own fixtures.** AGENTS.md's own "External procedures"
    section already states poc's `["C", ...]`-bracket external-procedure
    syntax is Peaseblossom's own invented extension, not one voc shares;
    confirmed directly by handing voc a module using it and getting a
    real parse error (`err 38 identifier expected` at the `[` token).
    Combined with there being no `rtl/llvm` `Console`/`Out` module yet
    (poc's LLVM backend has no voc-compatible I/O path at all), every
    runtime fixture built across steps 6–12 is unrunnable under voc,
    because every one of them needs that exact FFI mechanism just to
    print an observable result. "Cross-check against `voc` ... where
    practical" is therefore not achievable for those fixtures without
    first building real standard-library I/O (out of Phase 8's own
    scope, deferred to Phase 10's "full `Out.Mod`/`In.Mod`" — Phase 9
    added real language features but, like Phase 8, kept using the same
    direct-FFI `SysWrite` pattern for every fixture's own output).

    It *is* achievable for a narrower kind of fixture: one whose own
    core logic needs no FFI at all, only its final result print does.
    `semantic-const-decls`'s own CONST section is exactly this shape,
    but as written it isn't codegen-promotable outright - it uses
    REAL/LONGREAL arithmetic and SET constructors, both explicitly
    `Unsupported` in `GenerateConstValue`/`GenerateSetExpr` (PLAN.md
    Phase 8 step 5 scope), and a named string CONST, which hits the same
    `Unsupported` path since only *literal* strings passed directly to a
    call are handled (`GenerateStringArgValue`, step 11). Trimmed to
    exactly the INTEGER/BOOLEAN/CHAR subset codegen does support -
    arithmetic including DIV/MOD, a later constant referencing an
    earlier one, BOOLEAN `&`/`OR`/`~` over TRUE/FALSE, a hex CHAR literal
    - and promoted as `llvm-const-decls` (compile+link+run+diff-stdout,
    `SysWrite`/OK-vs-FAIL pattern, matching every earlier Phase 8 runtime
    fixture). A second, deliberately near-identical module,
    `test/conformance/crosscheck/crosscheck.mod`, folds the exact same
    CONST expressions and runs the exact same OK/FAIL check under real
    voc, printing via `Console.String`/`Console.Ln` instead of the FFI
    hack (directory named after the module itself, `crosscheck`, rather
    than something more descriptive, purely so `testenv.sh`'s own
    generic per-directory-name executable cleanup actually removes it -
    voc names the executable after the MODULE identifier, which can't
    contain hyphens, the same reason `test/conformance/hello` is a bare
    single word). Both independently print "OK" - a real, if narrow,
    confirmation that poc and voc agree on Oberon-2 CONST-folding
    semantics (Oberon2.pdf Appendix A/§5) for this subset, not just on
    either compiler's own idiosyncrasies. `semantic-statements` was
    surveyed as a second promotion candidate but dropped: every
    statement form it exercises (IF/ELSIF, CASE over INTEGER and CHAR
    with range labels, WHILE, REPEAT, FOR with and without BY, LOOP+EXIT)
    is already covered, construct-for-construct, by the existing
    `llvm-control-flow` fixture from step 7 - promoting it would have
    been pure duplication, not new coverage. `semantic-expressions` was
    also surveyed and dropped for the same REAL/SET-out-of-scope reason
    as the original `semantic-const-decls`, compounded by its own
    ARRAY-OF-CHAR relational comparisons (`name1 = name2`, `name1 <
    name2`), which codegen has never implemented at all (no
    `memcmp`/`strcmp`-equivalent lowering exists) - trimming it down
    would have left little not already exercised elsewhere by
    `llvm-control-flow`'s and `llvm-predeclared`'s own relational/
    boolean checks.

    114 conformance tests pass (112 prior + `llvm-const-decls` +
    `crosscheck`), confirmed via `make test` after both fixtures were
    added and again after `make clean-tests` removed every generated
    artifact. This is Phase 8's final step; Phase 9 (full pointer/`NEW`/
    GC, type-bound dispatch, open arrays, 32-/64-bit parity across the
    whole suite) is next, followed by Phase 10 (a real `rtl/llvm`
    library, including `Out.Mod`/`In.Mod`, and self-hosting).

**Testing summary**: golden-file `.ll` diffs for steps 1–5 (nothing runs
yet), promoted to compile+link+run+diff from step 6 onward per the
`BACKEND=llvm` harness mode from step 3.

### Phase 9 — LLVM backend, full language parity

**Goal**: every language construct `Oberon2.pdf` defines, compiling and
running correctly through the LLVM backend, on both 32-bit and 64-bit
targets, on Linux and at least one BSD — the point at which the *entire*
conformance suite (not just a hand-picked subset, as Phase 8 step 13
promoted) can compile+link+run+diff. Deliberately *not* the point poc can
compile itself — see Phase 10 below for why self-hosting is a separate,
later gate.

**Explicit non-goals**: `SYSTEM.*` (Appendix C — `ADR`/`VAL`/`BIT`/etc.,
see Phase 10 below; a subset, `ADDRESS`/`ADR`/`GET`/`PUT`/`VAL`/`MOVE`, was
pulled forward into Phase 9 step 4) and everything MACRO-32/VAX (Phase 13) are out of
scope per the phase-to-report map, not this phase's; `DISPOSE` isn't
added because it doesn't exist in
`Oberon2.pdf` at all (§10.3's `NEW` has no explicit-free counterpart —
Appendix D3 is explicit that a collector, not the programmer, reclaims
unreachable blocks); `ASSERT` stays whatever this file's own "No
`ASSERT`" open design question above says when a step below reaches
`PredeclaredProcedures.Mod` lowering — not decided by this plan, and
picking it up is opportunistic, not required for this phase's own exit
gate, unless that question is resolved before then. Also explicitly not
this phase's job, despite being directly downstream of it: any real
`rtl/llvm` module beyond the GC (`Console.Mod`, `Out.Mod`/`In.Mod`,
`Files.Mod`, `Platform.Mod`, `Modules.Mod`, `Strings.Mod`, `Math.Mod`)
and the self-hosting bootstrap itself — both now Phase 10's own scope,
inserted between this phase and the former Phase 10 (VAX/VMS, renumbered
11 and then 12 below) specifically because self-hosting cannot succeed without a
real runtime library first (see Phase 10's own opening for the concrete
dependency: `voc`'s own `Files.Mod` represents an open file as `POINTER
TO FileDesc`, so even a from-scratch `rtl/llvm/Files.Mod` needs this
phase's own `POINTER`/`NEW`/GC work done before it can be written at
all).

**A carried-over gap from Phase 8, not new Phase 9 work but blocking
it**: `LLVMCodeGenerator.Mod`'s `Unsupported` fallback is hit today by
REAL/LONGREAL arithmetic and literals, named STRING constants, and SET
constructors (every one tagged "PLAN.md Phase 8 step 5 scope" in its own
source) — plus ARRAY-OF-CHAR and RECORD relational comparison, which was
never lowered at all (no `memcmp`-equivalent exists). None of these
presuppose `POINTER`/`NEW`/GC the way this phase's headline items do,
but the "entire conformance suite must compile+run+diff" exit gate below
can't be met while they stay `Unsupported` — `semantic-expressions`,
`semantic-const-decls`'s full (untrimmed) form, and others depend on
them. Folded into this phase's build order below (steps 2–3) rather than
left implicit, since Phase 8 step 13 already had to explicitly trim them
back out of two promotion candidates for exactly this reason. (Separately,
`rtl/llvm/Console.Mod` was also never actually built in Phase 8 — every
fixture that needed output declared `PROCEDURE ["C", "write"] SysWrite`
directly instead, Phase 8 step 6's own retrospective explicitly deferring
the real wrapper body to Phase 8 step 10, which shipped ordinary
procedure-with-body codegen but never came back to write it. That gap is
Phase 10's to close, not this phase's — every fixture in the build order
below keeps using the same direct-FFI `SysWrite` pattern Phase 8 already
established, since none of this phase's own new language features need
real formatted I/O to test, only the pass/fail marker every predeclared-
procedure/trap fixture since Phase 8 step 9 already uses.)

**Cross-cutting discipline, not its own step**: every new size-dependent
quantity this phase introduces — pointer width, a type descriptor's own
address width, `ProcTab`/`BaseTypes`/pointer-offset table entry widths,
a dope vector's length-field width — must be parameterized by
`MemoryLayout.Mod`'s existing word-size axis from the moment it's
written, not retrofitted once 32-bit support is checked at the end. This
is the same discipline Phase 4 built `MemoryLayout.Mod` around in the
first place (voc's own `History.md` warning about retrofitting this is
quoted there) and the same axis Phase 8 step 13's real datalayout bug was
found and fixed against — treat that bug as this phase's own cautionary
precedent, not just Phase 8's. The already-separate `-O2`/`-OC`
elementary-size-model axis is unrelated to pointer width and shouldn't
be conflated with it.

**Proposed build order** — each numbered step lands its own conformance
fixtures before the next starts, matching Phase 8's own incremental
style exactly.

1. **Runtime type descriptors (Appendix D5).** `LLVMTypes.Mod` emits one
   type descriptor per record type at run time: a `tag` value (the
   descriptor's own address), a `ProcTab` (bound-procedure addresses,
   indexed by a compile-time-known per-type-bound-procedure index),
   a `BaseTypes` table (one entry per extension level, `BaseTypes[i]` =
   the type descriptor address of the ancestor at extension level `i`,
   used for `v IS T`/type guards as `v^.tag^.BaseTypes[ExtensionLevelT]
   = TypeDescrAdrT`), and a pointer-offset table (byte offsets of every
   pointer-typed field in the record, feeding step 5's collector). Per
   the report's own Fig. D5.1, `ProcTab` and the pointer-offset table
   grow from opposite ends of the descriptor as extension adds more
   procedures/pointers — `RecordType`'s own `baseType`/`methods` chain
   (already fully built by Phase 4/6's front end) gives everything
   needed to compute both an extension level and cumulative
   `ProcTab`/offset-table contents by walking it. Purely static: no
   allocation, no dispatch call, no `NEW` yet — every descriptor is
   emitted as its own LLVM global constant, verified by golden
   `-emit-llvm-ir` diff plus hand-checking one non-trivial extension
   chain's layout against Fig. D5.1's own worked example (the report's
   `Node`/`CenterNode` family — already this project's own go-to fixture
   source, Phase 4/6/8 all having already used it).
   **Testing**: `llvm-type-descriptors-ir`, golden `.ll` diff over a
   base type, a one-level extension, and a two-level extension (to
   confirm growth direction and level numbering, not just presence).

   **Implemented 2026-09-19.** `LLVMCodeGenerator.Mod`'s
   `EmitTypeDescriptors` emits one LLVM constant per module-level record
   type, `@<Module>.<Type>.tdesc`, plus an alias `@<Module>.<Type>.tag`
   for its "tag" (the address a heap block will store and a type test
   will compare) — the section comment above `RecordSymbolBase` is the
   authoritative layout reference. Departures from Fig. D5.1's exact
   picture, all recorded there: every field is one target word wide
   (`iW`, so no padding on any target); `BaseTypes` is exactly
   `level+1` entries long rather than NIL-padded to a maximum depth (so
   `v IS T` must compare `extLevel` first — `v.extLevel >= T.level AND
   v.BaseTypes[T.level] = T's tag` — never read `BaseTypes` unguarded);
   and a three-word header (`size`, `extLevel`, `ptrCount`) sits at the
   tag so the collector can locate the pointer-offset table without a
   maximum extension depth. Pointer offsets are flattened through
   inherited fields, nested records, and fixed arrays (an `ARRAY n OF
   POINTER` contributes `n` entries). Verified against Fig. D5.1 by hand:
   `Node`/`CenterNode` on `i686` give offsets `4, 8` / `4, 8, 16`,
   exactly the figure's. Supporting changes: `Types.RecordTypeDesc` gained
   `moduleName`/`name` (set by `SemanticActions.NameRecordType` for a
   module-level named record, or the anonymous record directly under a
   module-level named `POINTER TO`, called `<pointer name>.base`), because
   a record imported through a `.sym` file is a *different*
   `RecordType` object than its home module built, so a descriptor symbol
   cannot be found by identity across modules; `LLVMTypes.TypeString*` now
   handles a record with a base type (a nested first-element struct,
   which reproduces `MemoryLayout.RecordSize`'s "extension starts after
   the base's whole size" rule exactly) and gives `POINTER`/`PROCEDURE`
   the bare type `ptr` (with `Unsupported`'s placeholder becoming `null`
   for it); `LLVMTypes.ExtensionLevel*/MethodSlotCount*/SlotMethod*/
   MethodSlot*` compute the shape (an override reuses its base's slot).
   Fixtures: `llvm-type-descriptors-ir` (both word sizes, each also
   handed to `clang -c`, since a golden diff alone doesn't prove the IR is
   valid), `llvm-type-descriptors-cross-module-ir`.

   **Known gaps carried forward, not fixed by this step:**
   - **Hidden members** - *resolved by step 4a below (2026-09-19).* A
     `.sym` used to omit unexported record fields and type-bound
     procedures, so a record extending an imported one saw a partial base
     (wrong field offsets, `size`, `ProcTab` slots, and missing hidden
     pointers in the offset table). It now carries them; see step 4a for
     the design, why poc differs from voc's numeric-fact `.sym`, and the
     enforcement that keeps them unreachable by name.
   - **Procedure-local and other anonymous records** get no descriptor
     and no name (`SemanticActions` names only module-level ones;
     `OpenProcedureBodyScope` re-resolves a procedure's local `TYPE`s at
     codegen time, so they aren't even the same `RecordType` objects the
     checker built). Nothing can allocate or test one until steps 5/6, at
     which point either a naming scheme (procedure-qualified) or an
     explicit refusal is needed.
   - **Type-bound procedure bodies** - *resolved by step 6 below
     (2026-09-19).* Each `ProcTab` entry names its symbol
     (`@<Module>.<RecordName>.<ProcName>`); step 1 `declare`d it so the
     IR was valid, and step 6 dropped the declares as it began emitting
     the real `define`s (LLVM rejects a `declare` and `define` of one
     symbol).
   - Unrelated pre-existing front-end quirk seen while writing the
     fixture: `ResolveQualidentType`'s forward-reference check compares
     `obj.declLine >= node.line`, so a type used on the *same source line*
     it is declared on (`Anon = POINTER TO RECORD next: Anon END;`, or
     `A = INTEGER; B = ARRAY 3 OF A;` on one line) is rejected as a
     forward reference. voc accepts it.

2. **REAL/LONGREAL arithmetic, literals, and conversions.** Floating-
   point `EmitBinOp`/`EmitConvert`/`EmitCompare` lowering, replacing the
   REAL/LONGREAL branches of `Unsupported` named above. `-O2`/`-OC`
   don't affect `REAL`/`LONGREAL` width (this file's own resolved open
   design question already says so), so this is the one area in this
   phase genuinely independent of the word-size/size-model discipline
   above.
   **Testing**: promote (or extend) a runtime fixture exercising
   arithmetic, real division (`/`), `DIV`/`MOD` still integer-only,
   comparisons, and `LONG`/`SHORT` conversions between `REAL`/`LONGREAL`.
   **Implemented 2026-09-19.** Everything above, plus `ENTIER` and the
   integer forms of `LONG`/`SHORT` (the same instructions, a few lines
   more, and `ENTIER` is the only real-to-integer conversion). Outcomes
   worth knowing:
   - **A real numeral is echoed as text, not re-derived from its folded
     value.** `ConstantEvaluator.ParseReal` accumulates error (`0.1`
     is built from a running `scale / 10`), so `Types.Value.realVal` can
     be an ulp off the number the programmer wrote — harmless for
     folding, wrong for emission. `Types.ValueDesc` gained `realText`,
     the numeral's own source text (kept through unary minus by
     `ConstantEvaluator.NegateRealText`, empty for a computed value), and
     `LLVMCodeGenerator.RealConstant` writes that to LLVM's own
     correctly-rounded parser (`D` exponent letter → `e`). Only a
     computed `CONST` (`1.0D0 / 3.0D0`, `-third`) falls back to the folded
     value, emitted as its IEEE-754 bit pattern (`0x…`, built by exact
     power-of-two scaling rather than a bit-cast, which strict
     Oberon2.pdf source has no spelling for).
   - **`REAL` cannot use either obvious spelling in LLVM 22.** A decimal
     `float` literal must be exactly representable in single precision
     (`float 0.1` is "floating point constant invalid for type"), and
     `fptrunc` constant expressions no longer exist. A `REAL` numeral is
     therefore an `fptrunc double <numeral> to float` *instruction* —
     decimal to double to float, a double rounding that differs from a
     direct decimal-to-float conversion only for a numeral within 2^-29
     (relative) of a float midpoint. A computed `REAL` `CONST` is
     rounded to single precision first, then emitted as hex.
   - **Real division is always real**: `7 / 2` is `3.5` (`REAL`), so `/`
     on two integers converts both with `sitofp`; `DIV`/`MOD` stay
     integer-only (the front end already rejects real operands).
   - Comparisons use ordered `fcmp` predicates and `une` for `#`, so
     every relation but `#` is false against a NaN — C's behavior, and
     what voc's generated C does.
   - `ABS` on a real clears the sign bit through bitcast-and-mask rather
     than an `llvm.fabs` call, which would need a `declare` tracked
     program-wide; this also gets `-0.0` right.
   - The new fixtures: `llvm-reals` (56 run-time checks, all with exact
     or deliberately-chosen rounding cases; also cross-checked against
     real voc — see below) and `llvm-reals-ir` (golden `.ll` at both word
     sizes with clang validation, including the bit patterns of a
     subnormal and a large power of two, checked independently).
   - **Three voc quirks found**, recorded in `AGENTS.md`'s "Known voc
     bugs": voc rejects a `LONGREAL` literal that is integral and at
     least 2^31 (`1.0D10`) with "Value out of range"; it constant-folds
     `LONG(SHORT(x))` to `x`; and it prints REAL/LONGREAL constants into
     its generated C with only 8/15 significant digits. The last is why
     three of `llvm-reals`'s checks (27, 44, 51 — exactly the
     single-precision-rounding ones) fail under voc but pass under poc.
   - Still `Unsupported`: `MAX`/`MIN` on `REAL`/`LONGREAL` (also not
     folded by `ConstantEvaluator`), `ASH`, `SIZE`, `INCL`/`EXCL` — step
     8's sweep.

3. **SET constructors/operators, named STRING constants, and
   ARRAY-OF-CHAR/RECORD relational comparison.** The remaining
   `Unsupported` fallbacks named above: `{...}` SET constructor codegen
   (element/range list to bitmask), a named STRING `CONST`'s own value
   (`GenerateConstValue`'s `stringValue` branch — distinct from a
   literal passed directly to a call, already handled since Phase 8 step
   11), and `=`/`#`/`<`/`<=` over `ARRAY OF CHAR` and record-field-wise
   equality where the front end already permits it. Once this and step
   2 land, revisit Phase 8 step 13's own trimmed `llvm-const-decls`/
   `crosscheck` pair and the fixtures it explicitly passed over
   (`semantic-expressions`, the untrimmed `semantic-const-decls`) — some
   should now promote cleanly without trimming.
   **Testing**: a SET-operations fixture, a named-string-CONST fixture,
   an ARRAY-OF-CHAR-comparison fixture; re-run the Phase 8 step 13
   promotion survey and land whichever candidates are now unblocked.
   **Implemented 2026-09-19.** All of the above, plus `IN` and
   `INCL`/`EXCL` (which `PLAN.md` step 8 had earmarked for its sweep, but
   are SET operators no less than the constructor is), and assignment of
   a string to a `CHAR` array. Outcomes worth knowing:
   - **`IN` was not lowered at all** before this step - not just for
     sets built from constructors: `GenerateBinaryExpr` had no branch
     for it, so it fell to "unrecognized binary operator". `x IN s`
     checks `0 <= x < width` at x's own width first (an unsigned
     compare, so a negative x fails too) and `select`s the shift's
     result away when it does not hold, giving "not in the set" for an
     out-of-range element instead of an LLVM poison value (Oberon2.pdf
     leaves it undefined; voc's C shifts and inherits C's undefined
     behavior). A `select` rather than an `and`, since `and` would itself
     be poisoned.
   - **A SET constructor** is the OR of one mask per element: `1 shl e`,
     or, for a range `lo..hi`, `(-1 shl lo) and (-1 lshr (W-1-hi))`, which
     is empty by itself when lo > hi. Elements are converted to the SET's
     width first (`sext`/`trunc`) - an element may be any integer type,
     including `HUGEINT` under `-O2`'s 32-bit SET - and need not be
     constant.
   - **The AST has no resolved types**, so whether an operand is a
     character sequence has to be decided before it is generated:
     `DesignatorStaticType`/`IsCharSequenceExpr` walk the declarations
     without emitting anything, and `GenerateBinaryExpr` picks the whole
     lowering from that. (`GenerateDesignatorValue` for an array still
     loads the aggregate, which whole-array assignment relies on; a
     character sequence is instead used by address plus a compile-time
     length, never as a loaded value.)
   - **Character-sequence comparison** is one call to a private
     `@.charcmp` helper (three-way, unsigned bytes, a sequence ends at
     its first `0X` *or* at the end of its array). `COPY` from a
     non-literal source calls `@.charcopy`; from a string or named
     constant it stays the unrolled byte stores it always was, now shared
     with assignment (`EmitStringStores`). Both helpers, and the string
     globals, are emitted *at the end of the program and only if used*
     (`Codegen.needCharCompare`/`needCharCopy`/`pendingStrings`), so
     every earlier golden `.ll` stayed byte-identical.
   - **A named STRING `CONST` has no storage**, so its text becomes a
     private global on first use, deduplicated by content
     (`@.strconst.N`, `StringConstGlobal`) - by content rather than by
     position because an imported constant's position in a regenerated
     `.sym` bears no relation to its home module's. A one-character
     string, literal or named, in a *scalar* position (`ch := "x"`,
     `ch = "x"`, a `CHAR` argument) is a `CHAR` immediate, which also
     closes the gap `llvm-predeclared`'s header comment documents.
   - **Records:** `Oberon2.pdf` has no record comparison and the front
     end (correctly) rejects it, so there is nothing to lower - the
     "record-field-wise equality" in this step's own text was a
     misreading of "where the front end already permits it".
   - **Still not done**, for later steps: a character sequence behind a
     pointer or in a record with a base type (steps 5-6 - the address
     cannot be computed yet), and an *open* `ARRAY OF CHAR` operand or
     parameter (step 7's dope vectors) - either falls back to the same
     `; unsupported` placeholder as before. (All three done by steps 5-7.)
   - **Two voc differences found**: voc rejects a *constant* SET range
     with lo > hi at compile time (`{5 .. 2}`), which poc's front end
     does not, so the fixture uses a non-constant one; and voc's
     character-array comparison scans past the end of an array with no
     `0X` in it (undefined), where poc stops at the array's end - the one
     check of `llvm-char-arrays` (21) that fails under voc, everything
     else in it and all of `llvm-string-consts` agree.
   - **Fixtures** (127 tests pass): `llvm-sets` (35 checks; 32 also under
     voc), `llvm-string-consts` (two modules, identical output under
     voc), `llvm-char-arrays` (43 checks), `llvm-sets-strings-ir`
     (golden `.ll` at both word sizes, clang-validated, including both
     helper functions). **Promotion survey redone:** `llvm-const-decls`
     and `crosscheck` regained everything Phase 8 step 13 trimmed
     (`pi`/`widened`/`half`, `greeting`, `aSet`/`combinedSet`/
     `isMember`) - the CONST section is now `semantic-const-decls`'s own,
     complete, and voc and poc still both print `OK`; and
     `semantic-expressions` is promoted as `llvm-expressions-supported`
     (not run - its VARs are never assigned, so `i DIV j` would divide
     by zero - but every expression in it now lowers with no
     `; unsupported` marker, and clang accepts the IR).

4. **Bespoke mark-sweep GC (`rtl/llvm/GarbageCollectedHeap.Mod`,
   `ModuleTable.Mod`).** A bump-allocating heap plus a mark-sweep
   collector (the locked-in decision: no external C allocator/collector
   dependency), using step 1's pointer-offset tables to trace a live
   record's own outgoing pointers during mark, and a whole-program root
   set assembled from every loaded module's global pointer-typed `VAR`s
   — `ModuleTable.Mod` is the registry each module's init function
   registers itself into (mirroring voc's own module-table precedent
   named in this file's directory layout), and `LLVMCodeGenerator.Mod`
   gains its own per-module "which globals are GC roots, and at what
   offsets" table generation, the module-scope analogue of step 1's
   per-record one. Written as genuine Oberon-2 source, tested via the
   same direct-FFI `SysWrite` pattern every Phase 8 fixture already
   uses (Phase 10's own step 1 is what proves a *poc-compiled* rtl
   module can be `IMPORT`ed and run — this step doesn't need that
   machinery yet, only a working allocator/collector any fixture under
   test can call into directly). Collection can be purely allocation-
   triggered (no separate `SYSTEM`-level manual trigger — nothing in
   `Oberon2.pdf` exposes one); no compaction, no generations, no
   finalization — matching the "bespoke mark-sweep... no external C
   dependency" decision's own evident scope, nothing fancier.
   **Testing**: a standalone allocation/collection stress fixture
   (allocate many short-lived records in a loop, confirm memory is
   actually reclaimed — e.g. via a `SYSTEM`-free observable proxy like
   allocation count vs. a small fixed heap ceiling, not raw RSS).

   **Revised design (2026-09-19, decided with the user).** Two things in
   the text above do not survive contact with the code, and a third was
   missing:
   1. *"Genuine Oberon-2 source" needs raw memory access, and the only
      spelling of that in `Oberon2.pdf` is `SYSTEM` (Appendix C) - which
      Phase 10 step 7 schedules after this step, while `POINTER`/`NEW`/
      dereference codegen is step 5.* Resolved by **pulling a `SYSTEM`
      subset forward into this step**: the pseudo-module itself,
      `SYSTEM.ADDRESS`, `ADR`, `GET`, `PUT`, `VAL`, `MOVE`. Phase 10
      step 7 keeps the rest (`BYTE`, `PTR`, `BIT`, `LSH`, `ROT`,
      `SYSTEM.NEW`) and its own fixtures; nothing there changes except
      that it starts from a working front-end/back-end foundation.
      `SYSTEM.ADDRESS` is an integer type of *target word width*, ranked
      between `LONGINT` and `HUGEINT` in the numeric hierarchy.
   2. *The plan's root set (module-level pointer `VAR`s) omits the
      stack.* A pointer held only in a procedure's local or parameter is
      just as live, and a collector that misses it frees objects out
      from under running code. Poc has no stack maps, so the collector
      scans the stack **conservatively** (any word that points into a
      heap block keeps that block alive), the same approach voc's own
      `Heap.Mod` takes. Registers are spilled by a `setjmp` in the
      collector; the stack base is recorded by the program's `main`
      (`llvm.frameaddress`), which is the outermost frame anything can
      live in. Heap objects and module globals stay *precise* (step 1's
      pointer-offset tables and the new per-module root tables).
   3. *`ModuleTable` is a registry, not a module the program always
      has.* A program pays for none of this unless it imports
      `GarbageCollectedHeap`/`ModuleTable` (explicitly for now - step 5's
      `NEW` lowering adds the import implicitly): the backend emits each
      module's root table and its registration call only when
      `ModuleTable` is in the program.
   Heap shape: chunks obtained from libc (`calloc`, the one OS-facing
   dependency, declared through the existing FFI), each carved into
   16-byte-granule blocks laid out `[size|mark word][tag word][data]`;
   bump allocation within the current chunk, a first-fit free list of
   swept blocks ahead of it, collection when both fail, then a new
   chunk (up to a settable ceiling, so a fixture can prove reclamation
   against a small fixed heap). A per-chunk bitmap of block starts makes
   the conservative scan able to ask "is this word inside a block, and
   which". Marking is iterative with an explicit mark stack (deep lists
   cannot overflow the machine stack), falling back to a heap rescan if
   the mark stack itself overflows. No compaction, generations or
   finalization, as above.

   **Implemented 2026-09-19.** Everything above, with these departures
   and findings (`rtl/llvm/GarbageCollectedHeap.Mod`, `ModuleTable.Mod`;
   the `SYSTEM` subset; per-module root tables in `LLVMCodeGenerator.Mod`):
   - **`SYSTEM` subset.** `SYSTEM` is a pseudo-module with no source or
     `.sym`: `SymbolTable.SystemScope` holds `ADDRESS`, `ADR`, `GET`,
     `PUT`, `VAL`, `MOVE` (all exported), and `ResolveImport` binds
     `IMPORT SYSTEM` (or an alias) straight to it - the whole-program
     walks in `Poc.Mod` skip the name. The procedures reuse
     `PredeclaredProcedures.CheckCall`'s by-name dispatch (no predeclared
     name collides with them, so a qualified `SYSTEM.ADR(x)` needs nothing
     else; the `.sym` writer prints `SYSTEM.ADDRESS` through its ordinary
     imported-type lookup). **`Types.Address`** is a distinct integer type,
     rank between `LONGINT` and `HUGEINT` (`hugeIntRank`/`realRank`/
     `longRealRank` moved up one): a `LONGINT` may be assigned to an
     address, not the reverse - unlike voc, where it is `LONGINT`'s
     alias. Its width is the target word (`LLVMTypes` reads
     `ConstantEvaluator.wordSize`, `MemoryLayout.BasicSize` takes it as a
     parameter now); `ExtendTo` gained the `trunc` case for the one shape
     where the included type is *wider* (`-OC`'s 64-bit `LONGINT` on a
     32-bit target). Lowering: `ADR` = `ptrtoint` of the designator's
     address (so, for now, only designators `GenerateDesignatorAddress`
     can address - no pointer dereference until step 5), `GET`/`PUT` =
     `inttoptr` + a load/store **`align 1`** (an address has no alignment
     requirement in the report), `VAL(T, x)` = `ptrtoint`/real bitcast to
     an integer, `sext`/`zext`/`trunc` to `T`'s width, then `inttoptr`/
     bitcast (defined by poc for differing widths, where the report and
     voc leave it undefined), `MOVE` = `llvm.memmove` (declared once, at
     the end, only if used; a negative count moves nothing). `SIZE(T)`,
     which no earlier step had lowered, came along: it is a constant.
     Phase 10 step 7 has since done the rest, bar `GETREG`/`PUTREG`/`CC`
     and `SET64`.
   - **Register spilling is `llvm.eh.unwind.init`, not `setjmp`.** It is
     declared as an ordinary external procedure
     (`PROCEDURE ["C", "llvm.eh.unwind.init"] SpillRegisters;` - LLVM
     symbol names may contain dots), needs no libc, no `returns_twice`
     attribute, and cannot hide a pointer behind glibc's pointer-mangling of
     the saved registers. `Collect` calls it, then a *deeper* procedure
     (`MarkFromStack`) takes the address of one of its own locals as the
     top of the range to scan, so the spill slots sit inside it.
   - **The start map is one byte per granule**, not one bit: no bit
     operations to write (poc's `SET` is 32/64 bits and `ASH`/`LSH` are not
     lowered), for 1/16 of the block area. **Object size lives in the
     block header** (`size * 4 + inUse * 2 + marked`), and a tag describes
     *one element* - an object of several elements (an array of records)
     is traced element by element, `dataSize DIV size` of them, so step 5
     can give an array of pointers or of records the element type's
     descriptor; tag 0 = no pointers. The mark-stack overflow fallback is
     "re-trace every marked block until a pass does not overflow", rather
     than a per-block "scanned" bit the header has no room for on a 32-bit
     target.
   - **Root tables and the stack base are generated only when the
     program contains the module**: `@.roots.<Module>` (`{ next, count,
     slots }`, slot = address of a pointer location, flattened by the same
     `EmitPointerOffsets` the descriptors use, now taking an optional
     global symbol) is emitted, and registered at the top of `<Module>_init`,
     only if `ModuleTable` is in the program; `main` calls
     `GarbageCollectedHeap.SetStackBase(llvm.frameaddress(0))` only if
     `GarbageCollectedHeap` is. A program using neither has byte-identical
     output to before (every earlier golden held).
   - **No `NEW` yet, so the fixtures build descriptors by hand.** There
     is no source-level way to name a record's `.tag` (`SYSTEM.TYP` is not
     in Appendix C), so `llvm-gc-*` lay a descriptor out in a global array
     in the layout the section above `RecordSymbolBase` documents and pass
     its address to `Allocate`; objects are read and written through
     `SYSTEM.GET/PUT`. That layout is the *contract* the collector reads,
     and step 5's `NEW` is what first exercises it against a compiler-
     emitted descriptor - keep that in mind when it lands.
   - **Conservative scanning means false retention is possible, and the
     fixtures are written around it**: a stale stack slot can keep one
     dead object (and, precisely traced, whatever it points to) alive, so
     nothing asserts that a *specific* dead object is gone - only
     aggregate reclamation (a ceiling of 64 KB never exceeded while 3 MB
     are allocated, `LiveBytes` back near zero) and that live objects
     survive.
   - **Three things found and fixed on the way.** (1) `EmitIndexRangeCheck`
     compared a narrow index against the array length *in the index's own
     type*: a constant index is typed by its value, so `a[99]` is an `i8`
     and `icmp slt i8 99, 1024` reads the 1024 as 0 - every in-range access
     to such an array by a small constant trapped. It now widens first
     (`llvm-narrow-index`). (2) `ModuleInterface.ReadModuleSource` now
     tries `<Module>.Mod` after `<Module>.mod`, so the runtime library keeps
     the repository's spelling. (3) `Poc.Mod`'s whole-program walks skip
     `SYSTEM`. **Not fixed, found**: `SHORT` rejects a `HUGEINT` argument
     (`PredeclaredProcedures.CheckShort` lists only `LONGINT`/`INTEGER`/
     `LONGREAL`); open-array *parameters* still cannot be indexed or
     passed on (step 7's dope vectors, since built), which is why the
     collector and its fixtures pass only fixed arrays and scalars.
   - **Limits, recorded in the collector's own header:** one object at
     most 2^27 bytes; a chunk must not straddle the 32-bit signed
     boundary (address tests are offsets from the chunk start otherwise);
     chunks are never returned; no `free`. **32-bit verification
     (2026-09-19, after `glibc-devel.i686` was installed):** `llvm-i686-
     runtime` builds every runtime fixture (Phase 8's, steps 2-3's and
     both collector fixtures) as a real `i686-unknown-linux-gnu` ELF,
     runs it, and requires the output to equal its 64-bit sibling's
     `expected`; it skips itself (still passing, with a `SKIPPED` line)
     where `testenv.sh`'s `i686_can_run` finds no runnable 32-bit x86
     runtime. All 14 agree. It also found that `-target ... -build` had
     been linking for the *host*: `LLVMToolchainDriver.Build` never passed
     `--target` to `clang`, which merely warns about a module whose
     triple differs - fixed. `llvm-system`'s check 21 had assumed a
     64-bit address; it now compares against `SIZE` of a pointer.
   - **Fixtures** (133 tests pass): `llvm-system` (34 checks, 32 also
     under voc at `-O2` and `-OC`; two poc-only checks for `VAL` between
     widths), `llvm-system-ir` (golden at both word sizes, clang-checked),
     `llvm-gc-collect` (roots: plain/array/record; stack: local and interior
     pointer; reclamation against a ceiling; the ceiling stopping a program
     that keeps everything), `llvm-gc-tracing` (a 100-way fan-out against a
     4-entry mark stack, an object of four record elements, an object bigger
     than a chunk, coalescing of dead neighbours), `llvm-gc-roots-ir`
     (golden root table + `main`'s stack-base call at both word sizes),
     `llvm-narrow-index`. Disabling the stack scan, the
     module-table scan or the overflow fallback in a scratch copy of the
     collector makes the fixtures fail (the last, and the stack scan's
     knock-on damage, by hanging in a loop over a corrupted heap - there is
     no timeout in `poc_build_run`).

4a. **Hidden members in `.sym` files.** *(Numbered "4a" rather than
   renumbering steps 5–9, whose numbers are cited from source comments
   and from this file; it has no dependency on steps 2–4 and can land
   any time before step 5 — `NEW` needs a correct `size` for an imported
   base, and step 6's dispatch needs correct `ProcTab` slots. Found by
   step 1's cross-module work; decided with the user 2026-09-19.)*
   **The problem.** `ModuleInterface.Mod`'s writer prints only exported
   fields and exported type-bound procedures, so a module extending an
   *imported* record sees a partial base: missing fields shift the
   extension's own field offsets and its `size`; missing type-bound
   procedures shift the `ProcTab` slots its own new procedures get and
   under-count `MethodSlotCount(base)`. Any pointer-typed hidden field is
   also missing from the extension's descriptor offset table, which the
   step 4 collector would then fail to trace. (The base's own `.tag`
   symbol is unaffected — step 1 made that immune on purpose — but
   everything derived from the base's *shape* is wrong.)

   **What voc does, and why poc deliberately differs.** Checked against
   voc's own exporter (`OPT.Mod`'s `OutStr`/`OutFlds`/`OutHdFld`/
   `OutTProcs`, and `OPM.Mod`'s `ExpHdPtrFld = TRUE`, `ExpHdProcFld =
   FALSE`, `ExpHdTProc = FALSE`, `MaxHdFld = 2048`): voc does not export
   hidden members as declarations at all. Its binary `.sym` stores the
   record's computed `size`, `align`, and method-slot count `n`, each
   exported field with its numeric byte offset, each exported
   type-bound procedure with its explicit method number, and — the one
   hidden thing it does export — an anonymous `@ptr` entry (offset only)
   per hidden pointer, flattened through hidden nested records/arrays,
   for the importer's own descriptor. So `showdef` shows only the
   exported part because the format never held more, not because it
   filters; the compiler reads *computed layout facts*, not the hidden
   declarations. Those facts bake in a target: voc ships separate
   `2/sym` and `C/sym` trees per size model for exactly this reason. Poc
   wants one target-independent `.sym` usable at both word sizes and
   both size models (a stated Phase 4/8/9 goal), and Phase 7 decided
   `.sym` is valid Peaseblossom module source. Both are preserved by
   carrying the hidden *declarations* and letting the importer compute
   layout with `MemoryLayout` at its own target — the home module and
   every importer then use one algorithm and cannot disagree. Rejected:
   numeric-fact `.sym` (needs per-target files plus syntax the parser
   doesn't have), and a binary `.sym` (gives up "`.sym` is source", needs
   a separate dump tool, buys nothing this design lacks).

   **Design.**
   1. *Writer (`ModuleInterface.Mod`)*: print **every** field of every
      printed record type, in declaration order (layout depends on it) —
      exported ones with their `*`/`-` mark exactly as today, unexported
      ones as bare `name: T`. Likewise every type-bound procedure of every
      printed record type, in declaration order (slot numbering depends on
      it), unexported ones without a mark and still as permanently
      body-less `PROCEDURE^` forward declarations with their real
      signatures. `PrintMethods`' current gate (the receiver's own type
      identifier must be exported) goes away for methods of any record
      type that gets printed.
   2. *Unexported types the hidden members need*: print, as ordinary
      unexported `TYPE` declarations, every unexported named type
      reachable (transitively — a fixpoint, not one level) from a printed
      record's field types or a printed method's signature, in their
      original relative declaration order (so a definition precedes its
      uses exactly as in the source, and §4 rule 3's forward-`POINTER`
      exception still applies). Reachable-only, not "all private types":
      keeps `.sym` minimal and never drags in an unexported type nothing
      exported depends on. This replaces `FindInScope`'s
      `requireExported` structural-inline fallback for those cases — that
      fallback prints an unexported record *inline*, which would give two
      uses of one type two distinct anonymous `RecordType`s in the
      importer, breaking type identity; a named unexported declaration
      preserves it. It also preserves step 1's descriptor naming, since
      `Types.RecordTypeDesc.name` derives from the *declared* name, which
      must therefore round-trip through `.sym` unchanged. Types a hidden
      member takes from a third module need nothing new: the existing
      unconditional re-export of every import already covers them (what
      was an "occasional harmless extra import" is now load-bearing —
      update that comment).
   3. *Restore the export invariant on the reading side.*
      `SymbolTable.ObjectDesc.moduleScope`'s documented invariant —
      "holds exactly the exported members, so no separate export check is
      needed" — no longer holds. Every site that relied on it needs an
      explicit rule: (a) `SemanticActions.FindQualified` rejects an
      unexported object with a "not exported by module" diagnostic
      (`semantic-reject-not-exported` currently passes only because the
      name is *absent*, so its expected message changes); (b)
      `ModuleInterface.FindInScope` on an *imported* scope now needs
      `requireExported` too (its own comment currently says an imported
      scope is exported "by construction"); (c) field selection and
      type-bound-procedure calls across modules reject an unexported
      member unless `IsLocalType` says the record is local — the same
      helper the `-` read-only rule already uses (`CheckDesignator`'s
      `field.readOnly & ~IsLocalType(...)`); an unexported *method* needs
      the same gate in its own lookup path; (d) the backend's
      `ResolveQualifiedObject` runs only after the checker passed, so it
      needs no change, but its comment should stop claiming the scope is
      exported-only.
   4. *A stale `.sym` is now a correctness bug, not just a type-check
      one.* `-build`/`-emit-llvm-ir` type-check a module against its
      imports' *existing* `.sym` files (`ResolveImport`) but compile each
      import from its *real source* (`DiscoverModule`) — so an
      out-of-date `.sym` would give the importer's codegen a different
      record layout than the imported module's own. Fix: in the
      whole-program commands, regenerate `<Import>.sym` from real source
      for every transitive import that has source (post-order, before the
      importer is checked; into `-output-dir`, which lookup already
      consults ahead of the import path only via cwd, so verify that
      precedence when implementing) and fall back to a bare pre-existing
      `.sym` only for a source-less imported module. This also retires the
      "run `poc -emit-interface lib.mod` first" step every multi-module
      fixture currently repeats by hand. voc's answer to the same hazard
      is fingerprints (`pvfp` etc.); regenerating from source is simpler
      and is enough while every whole-program build has the source.
   5. *Optional, not a gate*: a `-show-interface` (stdout, exported view
      only) mode — the `showdef` analogue — by threading an
      `includeHidden` flag through the same writer. Cheap once the writer
      distinguishes the two; skip if it costs more than that.

   **Open questions to settle against `Oberon2.pdf`/real voc while
   implementing** (each becomes a fixture either way): (i) may an
   extension in another module declare a field or type-bound procedure
   whose name equals a *hidden* base member's? `Types.AddField` doesn't
   check inherited names today, and until now an importer couldn't even
   see the base's hidden ones; (ii) hidden-and-overriding type-bound
   procedures — voc reports its error 109 for one it "did not detect in
   OPP because record exported indirectly or via aliasing", so there is a
   real rule to match; (iii) whether an unexported type reachable only
   from a hidden member must itself avoid clashing with an importer's own
   declaration of that name — it must not, since it is never visible
   unqualified, but confirm `Insert`'s duplicate check is only ever run
   against the importer's own scope, not `moduleScope`.

   **Testing.** `module-interface-hidden-write` (golden `.sym`: a hidden
   field, a hidden pointer field, a hidden type-bound procedure, an
   unexported type reachable only through a hidden field, and one
   unreachable unexported type that must *not* appear); `semantic-reject-
   hidden-field-access`, `semantic-reject-hidden-method-call`,
   `semantic-reject-qualified-unexported-type` (plus the updated
   `semantic-reject-not-exported`); `module-hidden-extension-layout` (an
   importer extends a base with hidden members; its `SIZE`/`-dump-layout`
   view of the base equals the base's own, at both word sizes and both
   size models); `llvm-type-descriptors-hidden-members-ir` (cross-module
   golden `.ll`, extending step 1's `llvm-type-descriptors-cross-module-
   ir`: the importer's descriptor `size`, pointer-offset table including
   the hidden pointer, and `ProcTab` slot numbering all match the base's
   own, `clang -c`-validated); `module-hidden-roundtrip` (`-emit-interface`
   twice, the second time on the first's own `.sym`, byte-identical — the
   same technique `module-interface-real-roundtrip` uses); and
   `module-rebuild-stale-sym` (edit a hidden field in the library
   *without* re-emitting its `.sym`; `-build` must still lay the importer
   out against the new field). **On landing**, update: this file's step 1
   "Known gaps" bullet (remove it), `AGENTS.md`'s Phase 7 paragraph
   ("exported declarations only" is no longer true) and — a stale fact
   found while researching this — its voc source path, which says
   `/usr/local/sw/src/lang/Oberon/vishap/voc` but is actually
   `.../vishap/compiler`; `ModuleInterface.Mod`'s and
   `SymbolTable.Mod`'s header comments; `FindQualified`'s comment.

   **Implemented 2026-09-19.** Design as above, with these outcomes and
   deviations:
   - *Writer*: `ModuleInterface.Write*` runs its whole declaration-printing
     pass to a fixpoint with output suppressed (`dryRun`; `WriteStr`/
     `WriteLn` write nothing), collecting unexported types into a
     `NeededType` list (`NeedType`), then once for real - so marking and
     printing share `FindBoundName`/`FindOwnBound` by construction instead
     of a second, separate "mark" walker. Reachable types now include
     those referenced by exported `VAR`s and free-procedure signatures
     too, not only by hidden members, so an unexported record reached
     through an exported pointer (the `Tree`/`Node` idiom) is printed as a
     *named* unexported declaration instead of inline. That also fixes a
     step 1 mismatch: the inline form gave the importer's record the name
     `Tree.base` while the home module's was `Node`, i.e. two different
     descriptor symbols for one type. A name is only usable inside a TYPE
     declaration if declared earlier (or is the declaration's own name), or
     - a POINTER declaration's own direct base only - later (§4 rule 3);
     a predeclared basic type is always spelled by its Universe name. The
     former rule-free lookup also had a latent bug, fixed by this: two
     exported names sharing one type printed as the cyclic `A* = B;
     B* = A;`. Unexported types' own procedures travel with them; an
     unexported receiver type is printed too, so exported methods on it
     now reach importers (they used to be dropped).
   - *Reader*: `FindQualified` rejects an unexported object; a new
     `lookupDiagnosed` flag stops callers piling "undeclared identifier"
     on top of an already-reported "not exported"/"not an imported module"
     (`semantic-reject-import-not-on-path` lost that redundant second
     error). Field and type-bound-procedure selection judge the record that
     *declared* the member (`Types.FieldOwner`/`MethodOwner`), and locality
     is `rec.moduleName = currentModuleName` (`IsLocalRecord`; every
     `RecordType` is now stamped with its declaring module, named or not),
     which **replaces `IsLocalType`** and closes both its known loopholes
     (a local alias of an imported record; an anonymous record under a
     local pointer). The read-only `-` rule now uses the same owner-based
     test, so a local extension no longer makes an imported base's
     read-only field writable. An unexported CONST/VAR/PROCEDURE is still
     just absent from a `.sym` ("undeclared identifier"); only hidden
     types/members give the new "not exported" wording.
   - *Open questions, settled against real voc (probed 2026-09-19)*: (i) an
     extension may declare a field named like a hidden base field - two
     distinct fields; (ii) it may declare a type-bound procedure named like
     a hidden base one, any signature - a *new* procedure in its own slot,
     not an override, and no clash; (iii) an importer's own declarations
     never collide with a `.sym`'s hidden type names (`Insert` only ever
     runs against the importer's own scope). So hidden members count for
     layout and slot numbering but are invisible to name resolution and to
     overriding: `Types.FindOverridable` (exported, or declared by a record
     of the same module) decides what a declaration can override, and both
     the checker's `CheckOverride` and `LLVMTypes`' slot numbering use it,
     so they cannot disagree.
   - *Stale `.sym`*: `Poc.Mod`'s `RegenerateInterfaces` regenerates each
     transitive import's `.sym` from real source, post-order, before the
     top module is checked, for `-emit-llvm-ir` and `-build`; a source-less
     import keeps its existing `.sym`. Output goes to `-output-dir` (cwd by
     default) and `ModuleInterface.SetInterfaceDir` makes `ReadSource*` look
     there *first*, so a stale copy elsewhere cannot shadow a fresh one -
     this settled the precedence question flagged above. Fixtures for the
     whole-program path no longer hand-run `poc -emit-interface` for
     imports (older fixtures still do, harmlessly).
   - *Two further latent bugs* found while testing, both fixed:
     `ResolveProcDecls` used `FindMethod` (which walks the base chain) to
     decide whether a procedure body completes a forward declaration, so an
     override of an *imported* method found the base's `.sym`-loaded,
     permanently pending method and mutated it instead of recording the
     override (`Types.FindOwnMethod` now); and a function returning a
     pointer emitted the invalid placeholder `ret ptr 0` (now `null`, in
     both `GenerateProcedureDecl` and `GenerateReturnStatement`, alongside
     `Unsupported`'s).
   - *Fixtures* (names differ slightly from the plan above):
     `module-hidden-members` (golden `.sym` incl. transitive types, a
     third-module type, an unreachable type that must not appear, the
     alias fix; `.sym` round trip; importer/home layout agreement at all
     four word-size x size-model combinations), `semantic-reject-hidden-
     members` (hidden field, hidden method, unexported qualified type,
     hidden field through a local extension, plus the exported field of the
     same extension as the accepting control), `llvm-type-descriptors-
     hidden-members-ir` (cross-module golden `.ll` at both word sizes,
     `clang -c`-validated: the importer's size, pointer offsets including
     the hidden pointer, and `ProcTab` slots incl. a same-named new
     procedure beside the hidden one), `module-rebuild-stale-sym` (edits a
     hidden 8-byte field without re-emitting `.sym`; sized so a stale view
     would visibly disagree), and updated goldens for `module-interface-
     write` and `semantic-reject-import-not-on-path`.
   - *Not done*: the optional exported-view-only `-show-interface` mode -
     the writer would need only an `includeHidden` flag, but nothing needs
     it yet. `AGENTS.md`, `SymbolTable.Mod`'s header, `ModuleInterface.Mod`'s
     header, and the `FindQualified` comments are updated; the stale voc
     source path in `AGENTS.md` is fixed.

5. **`NEW` (fixed record/array), `POINTER`, `NIL`, `^` dereference,
   `IS`/type guards, and the `WITH` pointer guard.** `NEW(v)` lowers to
   step 4's allocator plus writing `v^`'s tag from step 1's descriptor;
   `v^.field`/`v^[i]` dereference through the allocated block (NIL-
   checked and trapped before every dereference — matching voc's own
   `-p` pointer-check convention, referenced but explicitly out of
   scope in Phase 8 step 9's own retrospective "NIL-dereference
   trapping... doesn't apply yet since there are no pointers in scope" —
   it applies now); `v IS T`/`v(T)` lower to the `BaseTypes` check
   step 1's own descriptors exist for. `GenerateStatement`'s own dormant
   `WITH` fallback and `RETURN`'s `s.value # NIL` arm (both flagged
   "until Phase 9/10 make it reachable" in Phase 8 step 7's
   retrospective) become real here. First step where a fixture can
   allocate, mutate, and observe a real heap-resident data structure.
   **Testing**: a linked-structure fixture (a small self-referential
   record chain — the report's own `Node`/list-building style examples
   are the natural source), a `NIL`-dereference trap fixture (matching
   the existing index-range/CASE trap fixtures' own pattern), a type-
   guard/`IS` fixture, and a real `WITH` fixture (abandoned as
   impossible in Phase 8 step 7, now buildable).

   **Implemented 2026-09-19.** Everything above, with these outcomes and
   departures:
   - *Dereference*: `GenerateDesignatorAddress` walks `.`/`[`/`^`/`v(T)`
     through pointers - `.`/`[` on a pointer load it, NIL-check it and
     continue from what it points to; `^` does the same explicitly; a
     field inherited from a base record is reached through one "element
     0" GEP per extension level (`GenerateFieldAddress`), an own field's
     struct index being one more than its declaration position when the
     record has a base. `DesignatorStaticType` mirrors it (and a WITH-
     narrowed variable, `Codegen.narrowings`). A NIL check is a compare and
     a branch to a trap: `nilderef` (exit 4). The trap-message globals for
     NIL/guard/WITH (exits 4/5/6) are emitted lazily, like
     step 3's helpers, so programs without pointers keep byte-identical IR.
     Pointer `=`/`#` needed nothing new (`icmp` on `ptr`); `NIL` is `null`.
   - *`NEW`*: `GenerateNew` for a pointer to a record or to a fixed array
     calls `GarbageCollectedHeap.Allocate(size, tag)` (tag = the record's
     `.tag` alias; for an array, 0 when its elements hold no pointers, else
     a synthesized `@.arraydesc.<n>` - the record-descriptor layout with
     size = ONE ELEMENT and no ProcTab, which is what the collector's
     "elements = dataSize DIV size" rule wants) and stores the result
     as the pointer - a 0 result (heap exhausted) becomes NIL, with no
     trap, exactly as voc's `NEWREC` does (an earlier draft trapped with
     exit 7; the report is silent, so voc's behavior wins). The next
     dereference of the NIL then traps like any other. `NEW` of an open
     array was step 7's (`; unsupported` until then). **The runtime is linked in implicitly**: a source
     module never imports `GarbageCollectedHeap`/`ModuleTable` for `NEW`,
     so `PredeclaredProcedures.NewWasCalled` (a process-lifetime flag set
     by `CheckNew`) tells `Poc.AddRuntimeModules` to discover the two on
     the import path (regenerating their `.sym` first), and to put them at
     the *front* of the module list (a program that imports them itself
     has them moved there). The runtime directory therefore has to be on
     `POC_IMPORT_PATH`/`-import-path`; there is no built-in default - a
     missing runtime is reported as an error naming the module, not
     silently mislinked. If the program lacks the module (a hand-built
     `ModuleList`), `Allocate` is `declare`d instead.
   - *Records with no descriptor*: `EnsureTypeTag` gives a record written
     inline under a `POINTER TO`, or declared inside a procedure, the
     unwritable name `$anon<n>` the first time `NEW`/`IS`/a guard/`WITH`
     names it (its base record first), and `EmitPointerSupport` emits the
     descriptor at the end of the program. Module-level records are as in
     step 1. Only a record of *another* module that is itself unnamed on
     this side (an inline record under an imported pointer) still cannot
     be named - `; unsupported`.
   - *`IS`, guards, `WITH`*: `EmitTagTest` reads the tag word before the
     data, then `BaseTypes[Level(T)]` - but only when the record is at
     least that deep (`extLevel >= Level(T)`; otherwise it reads
     `BaseTypes[0]`, which can never equal a non-root `T`'s tag), so the
     one-line report translation is branch-free after the NIL test.
     **NIL semantics** (the report is silent; probed against voc, which
     traps "NIL access" on all three, and matched exactly): `NIL IS T`,
     the guard `NIL(T)` and a NIL `WITH` variable all take the ordinary
     NIL-dereference trap (`nilderef`, exit 4) - `EmitTypeTest`/
     `EmitTypeGuard`/the WITH tests call `EmitNilCheck` first, so
     `EmitTagTest` never sees NIL. (An earlier draft made `NIL IS T`
     FALSE, the guard pass and the WITH variable match nothing; that
     accepted programs voc rejects at run time, so it was dropped.) A
     guard on a non-NIL pointer of the wrong type fails with `typeguard`
     (exit 5). Both the pointer and the bare-record spelling of `T` are
     accepted, as in the checker. `WITH` is an IF-chain; the branch body
     is generated with a `Narrowing` pushed, the string-literal pre-pass
     now walks `WITH` bodies (it did not - a literal inside a branch would
     have named an undefined global). Guards on a `VAR` record parameter
     (which needed the hidden tag argument) came with step 6.
   - *`&`/`OR` are short-circuited at last, always* (the Phase 8 step 5
     simplification was flagged "revisit once a call or a trap makes it
     observable" - a NIL check makes it observable): `GenerateShortCircuit`
     branches around the right operand and joins with a `phi` naming the
     block the right operand *finished* in (`Codegen.currentBlock`, kept by
     `EmitLabel`, whose signature therefore gained `cg`). A first version
     kept the eager `and`/`or` for a side-effect-free right operand
     (`IsSideEffectFree`); it was removed - two code paths for one
     operator bought only smaller IR for trivial operands, at the price of
     a purity predicate that had to track every future trapping operation
     (each new one, like an index or a NIL check, would have had to be
     added to it). Regenerated goldens: `llvm-reals-ir`,
     `llvm-straight-line-arithmetic` and `llvm-system-ir` (each diff only
     `and`/`or` becoming branch + `phi`), plus `llvm-pointers-ir` and
     `llvm-type-guards` (that, and `IS`/guards now NIL-checking instead
     of carrying a NIL branch).
   - *Other changes*: a local variable holding a pointer (or a record/
     array containing one) is `zeroinitializer`ed on entry - Oberon2.pdf
     6.4 says every pointer starts NIL, and it makes a never-assigned
     local a NIL trap rather than a wild access
     (`llvm-type-descriptors-hidden-members-ir`'s golden gained the store);
     `r1 := r2` where `r2` is an extension of `r1`'s type copies the base
     part (`extractvalue ..., 0` per level, `NarrowRecordValue`) - `clang`
     rejected the first attempt at the golden IR, which is what found it.
   - *Fixtures*: `llvm-pointers` (a `NEW`-built chain, zero-filled blocks,
     `^` record copy, pointers to fixed arrays, extension fields, `&`/`OR`
     over NIL), `llvm-pointer-shapes` (inline-anonymous and procedure-local
     records, `VAR` pointer and `p^` parameters, arrays of pointers, a
     record's embedded pointer array, function results), `llvm-pointer-
     fields` (string compare/`COPY`/`INC`/`INCL`/`LEN`/`CASE`/`FOR` through
     a pointer), `llvm-type-guards` (a three-level hierarchy plus a sibling:
     `IS`, guards as expressions and designators, `WITH` incl. `ELSE`; NIL
     operands live in `llvm-pointer-traps`, so the whole fixture now runs
     under real voc too and was cross-checked against it),
     `llvm-short-circuit` (call counters, index and NIL operands, the
     classic `WHILE (p # NIL) & ...` loops), `llvm-pointer-traps` (one
     program per trap: NIL through `.`, `^`, a chain, `[`, an unassigned
     local; `NIL IS T`, a guard and a `WITH` on NIL, each cross-checked
     against voc's own "NIL access" trap; a failed guard; an unmatched
     `WITH`; heap exhaustion, which is *not* a trap - `NEW` leaves NIL,
     as voc's does, and the program then prints and exits 0 until it
     dereferences it, while `heapfull` does so and traps with exit 4),
     `llvm-pointers-multi-module` (a pointer type, constructor and hidden
     field from an imported module; `NEW` of the imported record and of a
     local extension of it, laid out from the `.sym`; `IS`/guards/`WITH`
     across the boundary; objects from both modules linked into one chain
     under a small heap cap), `llvm-gc-new` (the collector driven by compiler-emitted descriptors
     and root tables: a 1 MB cap, several MB of garbage, a chain, an array
     of pointers, an embedded pointer array and a tree held only by a
     local survive; the same negative experiments as step 4 - no stack
     scan, no module tables - fail it), `llvm-pointers-ir` (golden `.ll` of
     the fixture's own part at both word sizes with register/label numbers
     normalized, so runtime changes cannot renumber it; `clang -c`
     validated), and all the runtime ones added to `llvm-i686-runtime`.
     `llvm-gc-new`'s reclamation checks are deliberately relative: the
     stack scan is conservative, and on i686 a stale word in a live frame
     kept a suffix of the chain alive (33 KB after dropping it, against 1
     KB on x86-64) - a real property of the design, not a bug.
   - *Known gaps, none new to this step*: `NEW(p, n)` and a pointer to an
     open array (step 7, done); type-bound calls (step 6, done); a procedure *value*
     (`proc := P`; comparing a procedure variable with `NIL` works, but
     naming a procedure as a value was `; unsupported` and, because
     `Unsupported` gives a mistyped placeholder, invalid IR; no step owned
     this, so it was listed under step 8, where it is done); a record value's LLVM type text is cut at 63
     characters (`ValueText`) - only a huge record loaded whole is
     affected, and it predates this step.

6. **Type-bound procedures and dispatch.** Each record type's `ProcTab`
   (step 1) is populated at module-init time with the addresses of its
   own bound procedures (inherited entries filled in from the base
   type's own slots where not overridden, per Fig. D5.1's layout);
   `t.P(...)` lowers to `t^.tag^.ProcTab[IndexP](...)`, and `P^(...)`
   (explicit base-method call, §10.3) indexes the *declared* receiver
   type's own `ProcTab` slot directly rather than dispatching. Receiver
   binding (`PROCEDURE (t: Tree) Insert...`) reuses ordinary-parameter
   codegen (Phase 8 step 10) with the receiver as an implicit first
   parameter.
   **Testing**: the report's own `Tree`/`CenterTree`/`Node` dispatch
   example (already this project's Phase 6 exit-gate fixture family) as
   a real compile+link+run+diff fixture — the natural capstone for
   dispatch, since it's the report's own canonical worked example and
   this project already has the front-end-only version of it checked.

   **Implemented 2026-09-19.** Points where `Oberon2.pdf` is silent or
   poc had to choose (all probed against real voc the same day):
   - *Bodies and symbols*: `GenerateMethodDecl` defines each type-bound
     procedure as `@<Module>.<Record>.<Procedure>` (a pointer-receiver
     `(t: Tree)` binds to `Tree`'s record; a record written inline under
     `Tree = POINTER TO RECORD` is `Tree.base`), receiver first, sharing
     `GenerateProcedureBody` with ordinary procedures - so step 1's
     `declare`s are gone (`EmitMethodDeclares` removed) and three
     descriptor goldens (`llvm-type-descriptors-*-ir`) gained the real
     bodies. The receiver is a bare `ptr` either way: a VAR record
     receiver is the record's address, a pointer receiver the pointer,
     which is the same address, so one calling sequence serves both.
   - *Hidden tag argument* (`NeedsHiddenTag`, decided here - the step 5
     note left it open): every VAR parameter of **record** type, a VAR
     receiver included, is passed as `ptr %x, ptr %x.tag` - the actual's
     type descriptor - because the actual may be an extension of the
     declared type and the callee must dispatch on, and test, what it
     really is (voc does the same). It sits right after its parameter; a
     `["C"]` external procedure gets the bare address (a fixture writes a
     record through `write(2)` to prove a tag would shift its
     arguments). VAR pointers, VAR arrays and value parameters carry none.
     The convention is part of the ABI of any procedure with such a
     parameter, so **procedure values** (step 8, done) pass the tag too.
     `DynamicType` says where an actual's tag comes from: a record
     variable, field or element is exactly its declared type (its own
     descriptor), `p^` is whatever the heap block says, a VAR parameter
     passes its own hidden tag on. Value record parameters take an
     extension too, copying only the base part (`NarrowRecordValue` now
     also applies to call arguments; real voc's generated C rejects this
     one).
   - *Dispatch* (`GenerateMethodCall`): `v.P(...)` calls through
     `tag - (slot+1)*W` when the receiver's dynamic type is not known
     exactly, straight to the procedure that slot holds for the static
     type when it is (`SlotOfMethod`, matched by `Method` identity, not
     name - hidden and new same-named procedures hold different slots).
     `v.P^(...)` is a direct call of the procedure `Types.FindMethod`
     finds on the base of `v`'s static type. A NIL pointer receiver is the
     ordinary NIL trap (exit 4), before the procedure starts; voc traps
     the same ("NIL access"). A pointer-receiver procedure needs a real
     heap block behind it (a callee may read the tag word), so calling it
     on a record variable is `; unsupported` rather than handed a
     "pointer" to a variable.
   - *Guards on VAR record parameters* (the front-end half was missing
     too; step 5 had assumed it existed): `IS`, `v(T)` and `WITH` accept
     a VAR parameter of record type, judged by
     `SemanticActions.lastDesignatorIsVarParam` since a designator's type
     alone cannot say. Matched to voc's own rules (its error 87): only
     the parameter's own name qualifies - a plain record variable, a value
     parameter, and `x(T)(U)` / `x(T) IS U` are rejected - while a guard
     and a test on the WITH-narrowed parameter inside its branch are
     accepted, and `v(T)` may be passed on as a VAR argument. The
     codegen tests the hidden tag (`EmitTagTestOnTag`,
     `EmitTypeGuardOnTag`).
   - *Discovered along the way, fixed*: an extension record passed to a
     value record parameter emitted an ill-typed call; a qualified
     variable (`M.v`) as a VAR argument was `; unsupported` for no reason.
   - *Fixtures*: `llvm-type-bound` (pointer receivers three levels deep
     plus a sibling, `^` chains, self-dispatch, receivers that are fields,
     array elements, guards, `WITH` variables and locals, VAR receivers on
     variables, fields, elements and heap blocks, a base pointer holding
     an extension, a bound procedure's own VAR record parameter, dispatch
     inside a short-circuited operand), `llvm-var-record-params` (the hidden tag: relayed,
     from `p^`/fields/elements/locals, two per call, `IS`/`WITH`/guards,
     a procedure-local record type, the external-`write` regression),
     `llvm-type-bound-multi-module` (overriding an imported procedure, a
     hidden imported procedure holding a slot its importer cannot
     override, library code dispatching to importer overrides, VAR
     receivers and VAR arguments of imported types, imported variables as
     receivers), `llvm-trees-dispatch` (the report's own `Tree`/
     `CenterTree` example with a recursive bound `Write` dispatching
     through pointer fields; its `Trees` module proper needed step 7's open
     arrays - `llvm-trees-strings` has it), `llvm-type-bound-ir` (golden `.ll` at both word sizes, `clang -c`
     validated), five `llvm-pointer-traps` programs (NIL through a
     pointer receiver, a VAR receiver and a `p^` VAR argument; a failed
     guard and an unmatched `WITH` on a VAR parameter) and three `semantic-*`
     fixtures. All the runtime ones also run as real i686 executables.
     Every behavior above was cross-checked against real voc except two
     things voc cannot do: a bound call through a record written inline
     under a `POINTER TO` (voc gives it no descriptor and traps "NIL
     access"; it is the fixture's last check for that reason) and
     extension-to-value-parameter (its C does not compile).
   - *Found, not fixed (pre-existing, unrelated)*: constant arithmetic on
     literals is not folded - `2 * 100 + 2 * 10` is typed `SHORTINT` and
     wraps at 8 bits at run time, where voc folds it to 220.

7. **Open-array dope vectors.** Open-array formal parameters (`VAR`
   and value) pass a hidden length parameter per dimension alongside
   the data pointer, matching voc's own convention already cited in
   Phase 8 step 4's retrospective; `NEW(v, x0, ..., xn-1)` (§10.3's
   multi-dimensional open-array allocation form, Appendix A's own
   table) allocates and populates the dope vector accordingly; `LEN`'s
   existing two-argument form (already lowered in Phase 8 step 11 for
   fixed arrays) extends to read a real dope-vector length at those
   dimensions rather than a compile-time-known one. Directly closes the
   one gap Phase 8 step 11's own retrospective explicitly called out and
   routed around ("forwarding an `ARRAY OF CHAR` value parameter into
   another call... stays unexercised... open arrays are a known,
   narrow, not-yet-built convention").
   **Testing**: an open-array `VAR`-parameter fixture forwarding a
   value between two procedures (Phase 8 step 11's own deferred case,
   finally exercised for real), and a multi-dimensional `NEW(v, x0, x1)`
   fixture.

   **Implemented 2026-09-19.** The convention (`LLVMCodeGenerator.Mod`'s
   section on open arrays has the reference text; every point probed
   against real voc, whose runtime source was read for the heap layout):
   - *Parameters.* An open-array parameter, `VAR` or value, is
     `ptr %a` then one `%a.len<d>` per open dimension (`OpenDimCount`),
     each a word-sized integer - the target's word size, like every other
     size-dependent quantity this phase (voc's are `ADDRESS`); an external
     `["C"]` procedure keeps the bare `ptr` (Phase 8 step 6's decision,
     unchanged - `ParamLLVMType`). A *value* parameter is copied on entry
     into an `alloca` of `product(lengths) * sizeof(element)` bytes with
     `llvm.memmove` (voc copies too - probed: assigning to the parameter
     leaves the caller's array alone). `MemoryLayout.DescriptorSize`'s
     "4-byte length words" became word-sized to match.
   - *Designators.* `DesignatorAddressTo`'s `DynamicType` gained a
     `DopeVector`: an open-array parameter's binding carries its lengths,
     `[` on one checks `idx <u len` (`EmitOpenIndexCheck`, at the wider of
     the index and the word, so a `HUGEINT` index on 32 bits is not
     truncated) and steps by the element (`EmitElementGEP`) - or, when the
     element is itself an open array, by the product of the inner lengths
     in bytes, leaving the address of the inner array and the remaining
     lengths (so `a[i, j]`, `a[i][j]` and `a[i]` passed on all work).
   - *Arguments.* `GenerateOpenArrayArg` takes any array designator (fixed
     dimensions contribute their constant length, open ones the dope
     vector's) and, for a value `ARRAY OF CHAR`, a string literal or named
     `STRING` constant (length = characters + 0X, as voc's `LEN("abc")`).
     `GenerateStringArgValue` is gone; `GenerateCharSequence` reports a
     word-sized length text instead of a `LONGINT`, so comparison and
     `COPY` take open `ARRAY OF CHAR`s (`EmitLengthAsI32` narrows, clamping,
     for the `i32` helpers).
   - *Pointers.* `POINTER TO ARRAY OF ...` points at a block laid out as in
     voc: the lengths (one word per open dimension), then the elements at
     `OpenDataOffset` (the lengths rounded up to the element's alignment).
     `DereferencePointer` loads the lengths into the designator's dope
     vector and continues from the first element. `NEW(p, n0, ..., nk-1)`
     (`GenerateNewOpenArray`) does the size arithmetic in 64 bits with
     `llvm.umul/uadd.with.overflow` (a 32-bit target must also fit a word),
     traps - new exit 7, voc's own message for its `Halt(-20)` - when any
     length is not positive or the size overflows, allocates through
     `GarbageCollectedHeap.Allocate`, stores the lengths if a block came
     back (NIL, not a trap, if not - as for a record) and then the pointer.
   - *Collector.* The block's tag is the array descriptor of the innermost
     element type (`ArrayTagOperand`, `InnermostOpenArray`), as for a fixed
     array of pointers. The collector walks a block as a run of elements
     from its start, so when the elements hold pointers `OpenDataOffset`
     rounds the header up to a whole number of elements: the lengths are
     then read as a few elements' pointer fields, a spurious candidate at
     worst (they are at most 2^25, below any heap address).
     `llvm-open-array-new` fails if the descriptor is dropped (checked).
   - *Front end.* One gap surfaced: `CheckArguments` demanded the *same*
     type of a `VAR` open-array parameter's argument (`Types.SameType`,
     which two independently written open-array types never satisfy),
     so an open array could not be forwarded, and a fixed one could not be
     passed to a `VAR ARRAY OF` at all - now `IsOpenArrayFormal`
     (`Types.ArrayCompatible`). voc accepts and rejects exactly the same
     sets (both semantic fixtures were run through it).
   - *Also fixed*: `LEN` was typed `INTEGER` by the code generator but
     `LONGINT` by the checker, so a length above 32767 wrapped -
     `GenerateLen` now returns `LONGINT` (`llvm-predeclared-ir`'s golden
     changed by exactly that).
   - *Testing.* `llvm-open-array-params` (`VAR` and value parameters,
     forwarding, a value parameter's private copy, 1- and 2-dimensional
     arrays given fixed arrays and rows, strings, `COPY`, comparison,
     records as elements, recursion, a bound procedure, an open array
     handed to an external C procedure), `llvm-open-array-new`
     (`NEW(v, n)`, `NEW(m, n, k)`, a 3-dimensional one, an open outer
     dimension over a fixed element, characters, arrays reached through
     record fields, an index wider than a word, and the collector run over
     50 pointer-holding arrays), `llvm-trees-strings` (Chapter 11's `Trees`
     as a library - `Insert(name: ARRAY OF CHAR)`, `NEW(p.name,
     LEN(name)+1)`, `COPY`, `name = p.name^` - across a module boundary),
     `llvm-open-array-traps` (index past either end, through a parameter, a
     pointer and the inner dimension; NIL element and NIL `LEN`; zero,
     negative, inner-zero and overflowing lengths; a too-big request
     answering NIL), `llvm-open-array-ir` (golden `.ll` at both word
     sizes, `clang -c` validated) and two `semantic-*` fixtures; the
     runtime ones also run as real i686 executables (the trap programs by
     hand). Cross-checked against real voc: every check of the first three
     agrees except the one below.
   - *Found, not fixed*: voc passes `a[r]` of a multi-dimensional open
     array with no row stride (AGENTS.md, "Known voc bugs"), so one check
     of `llvm-open-array-params` differs under voc - poc is right. voc
     rejects a constant length <= 0 in `NEW` at compile time; poc traps at
     run time. An open array with more than 8 dimensions, and elision of a
     value parameter's copy when it is never written, are not done.

8. **Complete `PredeclaredProcedures.Mod` lowering.** Sweep whatever
   remains `Unsupported` once steps 1–7 land — expected to be a short
   list by this point, since `NEW` (step 5), `LEN`'s open-array form
   (step 7), and every REAL/SET-related gap (steps 2–3) are the only
   §10.3 procedures Phase 8 step 11's own retrospective named as out of
   scope. Pick up `ASSERT` here only if this file's own open design
   question above has been resolved by then; otherwise leave it exactly
   as undecided as it is now.
   Also here: procedure *values* (`proc := P`, passing a procedure as an
   argument), found unlowered by step 5's testing - `GenerateDesignatorValue`
   reports a procedure name `; unsupported`, and `Unsupported`'s placeholder
   for an untyped result is `0`, which is invalid IR where a `ptr` is
   stored.
   **Testing**: whatever fixture gaps steps 1–7 didn't already close on
   their own.

   **Implemented** (2026-09-19; all probed against real voc). What
   changed, and what a program can observe:
   - *Procedure values.* A procedure's name used as a value is the address
     of its function (`ptr @Module.Proc`, `GenerateDesignatorValue`); it can
     be assigned to a variable, record field or array element, passed as an
     argument (a `VAR` parameter of procedure type too), returned from a
     function, compared with `=`/`#` against another procedure-typed *value*
     or NIL, and called through any of them (`GenerateProcedureValueCall`:
     the designator is loaded, NIL-checked - the usual exit-4 trap, voc's
     "NIL access" - and called indirectly). The arguments are laid out from
     the procedure *type's* parameter list, hidden arguments included (a
     `VAR` record's tag, an open array's lengths), which is exactly what
     every procedure that matches the type expects - so `Inspect(VAR s:
     Shape)` called through a value still sees `s`'s real type. A local
     variable of procedure type (or a record/array holding one) is zeroed on
     entry like a local pointer (`ContainsProcedureValue`): poc guarantees
     that calling one never assigned traps, where voc leaves it as stack
     garbage. The collector is unaffected - a procedure holds no heap
     address, `CountPointerSlots` still skips it, and a record mixing
     procedure and pointer fields is traced whole (checked).
   - *Front end.* `CheckProcedureValue` (Oberon2.pdf 6.5: "P must not be a
     predeclared or type-bound procedure nor may it be local to another
     procedure") rejects a type-bound procedure (`CheckDesignator` now
     reports whether a designator ended in one, `lastDesignatorIsBoundProcedure`)
     and a nested one used as a value; poc also rejects an *external* one
     (it is called with the C convention, a procedure value with the Oberon
     one - there is no such thing in voc). A predeclared one already failed
     as not having a procedure type. And a procedure's *name* is no operand
     of `=`/`#` (`NamesProcedure`): Appendix A lets it stand for the
     procedure only in an assignment or as an argument, and voc agrees
     ("this expression cannot be a type or a procedure") - poc used to
     accept `f = P`. voc rejects the same forms with the same reasons
     (`semantic-reject-procedure-value`).
   - *ASH.* `ASH(x, n)` shifts left for `n >= 0` and right, sign-filling,
     for `n < 0`, in the wider of `LONGINT` and `x`'s own type -
     `CheckAsh` used to say `LONGINT` always, losing a `HUGEINT` operand's
     top bits; voc's own rule is "LONGINT, or INT64 if larger". A count of
     the type's width or more is not left to LLVM (poison): everything is
     shifted out, leaving 0 (or the sign, for a right shift) - identical to
     voc for counts up to 63, past which its C shift is undefined (those
     checks are `poc only` in the fixture). Branch-free, via `select`.
     voc computes in 64 bits and truncates on assignment, so a `LONGINT`
     result that overflowed compares differently *unnamed* (`ASH(1, 31) =
     MIN(LONGINT)` is false under voc) - the fixture stores it first.
   - *MAX/MIN.* `MaxMinBound` (now exported) already gave the constant
     folder every bound but REAL/LONGREAL; `GenerateMaxMin` emits them for
     the run-time expression form (`i := MAX(SHORTINT)`), and the two real
     types as their IEEE largest finite values and negations. voc's
     `MAX(LONGREAL)` is a deliberate underestimate (`OPM.Mod`:
     `1.7976931348623157D307 * 9.999999`, "should be ...D308"); poc gives
     the true one. `CONST` folding of `MAX(REAL)`/`MAX(LONGREAL)` is still
     not done (the entry under "Open design questions" stands).
   - *ASSERT* left exactly as undecided as before.
   - *Found and fixed on the way*: `AppendLongInt` emitted a bare `-` for
     the most negative `LONGINT` (`MIN(HUGEINT)`, or a `HUGEINT` constant of
     that value) since it negated the value to build the digits.
     `EmitConstantValue` split out of `GenerateConstValue` so a folded bound
     is emitted like a `CONST`.
   - *Testing.* `llvm-procedure-values` (41 checks: every place a value can
     live and be called through, argument passing two levels deep, results
     of each kind including a pointer and a procedure, hidden tag and
     lengths, locals, recursion through a variable, the collector),
     `llvm-procedure-values-import` (`Calc.Add` as a value, an exported
     procedure-typed variable and record field, across a module boundary),
     `llvm-procedure-value-traps` (a NIL procedure called as a global, a
     never-assigned local, a heap record's field, an array element, a
     proper procedure, a `NIL` argument, and through a NIL pointer - all
     exit 4, and all "NIL access" under voc), `llvm-procedure-values-ir`
     (golden `.ll` at both word sizes, `clang -c` validated),
     `llvm-ash-max-min` (62 checks, all three integer widths, `HUGEINT`
     operands and counts, every `MAX`/`MIN`) and
     `semantic-reject-procedure-value`; the three runtime fixtures also run
     as i686 executables (`llvm-i686-runtime`). Cross-checked against real
     voc (`llvm-procedure-values` and `llvm-ash-max-min` - minus the `poc
     only` part - print `OK` under it; the trap programs give "NIL access"
     each).
   - *The `Unsupported` placeholder* is no longer reachable with a pointer
     or procedure result: the sites that produced one (a procedure name as
     a value, a call through a value) are lowered, and the remaining ones
     take a type the checker has already fixed or are unreachable for a
     program it accepts.
   - *Not done*: `CONST` `ASH(...)`/`MAX(REAL)`, and folding of *integer
     literal arithmetic* (`2 * 100 + 2 * 10` wraps at `SHORTINT` width
     where voc folds it) - both pre-existing and unrelated to this step;
     they are step 10's (Catching Up).

9. **32-/64-bit parity sweep.** Run the *entire* conformance suite —
   not a promoted subset — compile+link+run+diff on both a 32-bit and
   a 64-bit LLVM target, on Linux and at least one BSD (reusing Phase 8
   step 13's real-hardware access, `erekose`/OpenBSD-i386 and
   `terhali`/NetBSD-x86_64, rather than assuming portability from a
   single platform). This is the phase's own explicit exit gate, listed
   here as its own step rather than folded into the individual feature
   steps above precisely because it must run *after* all of them, over
   everything at once, the same way Phase 8 step 13 only found the
   datalayout bug once real fixtures actually ran on real 32-bit
   hardware.
   **Testing**: `make test` clean on every combination; any fixture
   that only passes on one word size or platform is a real bug, not an
   acceptable gap, at this point in the project.

10. **Catching Up.** Three constant-folding gaps found while
    implementing steps 5-8, each pre-existing and none in those steps' own
    scope; all three make poc reject, or mis-type, something real voc
    accepts and folds. Listed after step 9 because none blocks the parity
    sweep (every fixture so far avoids them), but the sweep is re-run over
    the whole suite once this lands - see **Testing** below. Every
    behavior below is to be probed against real voc first (this file's
    standing convention), not assumed from the notes that found the gaps.
    - *Folding of integer literal arithmetic.* `2 * 100 + 2 * 10` is typed
      `SHORTINT` and wraps at 8 bits at run time; voc folds it to 220.
      `ConstantEvaluator.IntegerLiteralType` gives a bare numeral its
      minimal type (Oberon2.pdf §5), but a *computed* constant keeps the
      type of its operands: `Types.WiderOf` of two `SHORTINT`s, whatever the
      result's value needs. Two halves: (a) an ordinary *expression* whose
      operands are all constants (`SemanticActions.CheckExpr` and
      `LLVMCodeGenerator`, which never fold - the wrapping above happens
      there) is folded to a constant of the minimal type its value fits,
      as voc's `OPB` does; (b) `CONST` folding likewise re-derives the
      minimal type from the computed value instead of keeping the
      operands' (`000-todo.org`'s `MAX(SHORTINT) + 1` entry, which real voc
      rejects and poc types `SHORTINT`). Decide from voc's own behavior
      what happens when the value fits no type (`HUGEINT` overflow -
      `ConstantEvaluator` already reports "integer literal too large" for a
      numeral, so a computed overflow should be the same kind of error, not
      a silent wrap), and whether `DIV`/`MOD`, unary minus and the six
      relations fold too (they should: a constant expression is a constant
      expression). Both size models (`-O2`/`-OC`) change which type a value
      lands in, so the folder must use the current model, as
      `IntegerLiteralType` already does.
    - *`CONST` `ASH(x, n)`.* The first *value-argument* predeclared
      function `ConstantEvaluator` has to fold: `MAX`/`MIN`/`SIZE` take a
      bare type name and needed no general machinery (see "Open design
      questions"), but `ASH` must evaluate its two arguments as constant
      expressions and apply the shift. Same result type as
      `PredeclaredProcedures.CheckAsh` (the wider of `LONGINT` and `x`'s
      type). voc reports a constant `ASH` whose count is beyond the
      machine's `maxExp`, or whose left shift overflows 64 bits, as
      error 208 (numerical overflow) - probe the exact boundaries and match
      them rather than the run-time semantics `GenerateAsh` gives (which
      define a count past the width as 0/sign). Whether the same machinery
      is then extended to the other value-argument functions (`ORD`/`ABS`/
      `CHR`/`CAP`/`ODD`/`LONG`/`SHORT`/`ENTIER`, all deferred alongside)
      is optional here: `ASH` is what this step commits to, built so the
      others are one small case each.
    - *`CONST` `MAX(REAL)`/`MIN(REAL)`/`MAX(LONGREAL)`/`MIN(LONGREAL)`.*
      `ConstantEvaluator.MaxMinBound` still returns FALSE for these; the
      run-time expression form is done (`GenerateMaxMin`: IEEE 754's largest
      finite values, 3.4028234663852886D38 and 1.7976931348623157D308 - voc's
      own `MAX(LONGREAL)` is deliberately a little low, so poc's value
      differs from voc's by design, documented in AGENTS.md). The constant
      form has to build those two `LONGREAL` values inside poc's own
      source *without* writing them as literals - voc rejects a `REAL`
      literal with exponent 38 and a `LONGREAL` one with exponent 308
      (AGENTS.md, "Known voc bugs"), the same workaround
      `LLVMCodeGenerator.DoubleBitsText`'s `twoTo52` loop already uses (or
      assemble them arithmetically from their bit patterns). Then the
      folded value must round-trip through `ModuleInterface.Mod`'s
      `.sym` writer (a `CONST` exported from a module: tier 2's
      `FormatReal`, since it is not a bare literal) and be emitted by
      `RealConstant` exactly, including at `REAL`'s single precision.
    **Testing**: for each gap a positive fixture (`poc -check`, plus a
    compile+link+run one where the value is observable at run time -
    `2 * 100 + 2 * 10` compared with 220 is the direct regression), a
    negative one for what voc rejects (a folded overflow, `MAX(SHORTINT) +
    1` in a `CONST`, an `ASH` past `maxExp`), a `.sym` round-trip for a
    `CONST` of each new kind, all under both `-O2` and `-OC` where the
    size model matters, and cross-checked against real voc (the `MAX`
    constants excepted, by design, for `LONGREAL`). This step's fixtures
    are ordinary `make test` fixtures, so **the step 9 sweep is re-run in
    full** - both word sizes, Linux and at least one BSD - after it lands,
    and Phase 9 is not done until it is clean.

    **Implemented** (2026-09-19; every behavior below probed against real
    voc, both size models). What changed, and what a program can observe:
    - *Folding integer arithmetic.* A constant integer operation is carried
      out in 64 bits (`ConstantEvaluator`: `SumOverflows`/
      `DifferenceOverflows`/`ProductOverflows`, `IntegerResult`), whatever
      the operands' types, and its result takes the *minimal type its value
      fits* (`MinimalIntegerType`, which `IntegerLiteralType` now shares) -
      `2 * 100 + 2 * 10` is the INTEGER 220, `MAX(SHORTINT) + 1` an INTEGER,
      and `-128` a SHORTINT though `128` is an INTEGER (unary minus re-types
      too; unary `+` folds now). It is an error only when the value does not
      fit HUGEINT, where voc's `OPB.ConstOp` reports errors 203-207: "constant
      sum/difference/product/negation too large for HUGEINT". A constant
      `DIV`/`MOD` folds floored; a zero divisor is "division by zero", as
      before. Integer constants compare as integers now (`EvaluateEquality`/
      `EvaluateOrder` went through LONGREAL, so a `CONST` `MAX(HUGEINT) =
      MAX(HUGEINT) - 1` was TRUE). This is one mechanism for `CONST`
      declarations and for ordinary expressions: `ConstantEvaluator.
      IsConstantExpr` (silent - `Evaluate` reports) says whether every leaf
      is a literal, a named constant, `MAX`/`MIN`/`SIZE` of a type name or a
      constant `ASH`; `SemanticActions.FoldIntegerConstant` (`CheckExpr`,
      for a unary or binary expression or an `ASH` call) then gives the
      expression the folded value's type, and `LLVMCodeGenerator.
      GenerateFoldedInteger` emits the folded value as one immediate of that
      type, so the checker and the generator cannot disagree. Only an
      *integer-typed* result is folded: a constant real, BOOLEAN or SET
      expression is left to the rank rules and to LLVM (it can neither wrap
      nor be mistyped), and so is a relation of two constants - an error
      inside one (a division by zero) is still found, in the operand.
    - *Two host bugs worked around, one voc bug not reproduced.* poc is built
      with voc, whose `DIV`/`MOD` are wrong for a negative dividend within
      the divisor of `MIN(LONGINT)` (`MIN(LONGINT) DIV 2` comes out positive),
      so `FloorQuotient`/`FloorRemainder` never divide such a value, and
      `ProductOverflows` uses no negative dividend either. As a result poc
      accepts a product of exactly -2^63 (`(-2^62) * 2`), which voc rejects
      (its own check divides `MIN(INT64)`, apparently through the same bug). `MIN(HUGEINT) DIV (-1)` is "constant quotient
      too large" - voc's compiler dies of SIGFPE folding it.
    - *`CONST` `ASH(x, n)`* (`EvaluateAsh`): both arguments constant
      integer expressions; a count outside -62..62 (voc's `maxExp`) or a left
      shift with `ABS(x) > MAX(HUGEINT) DIV 2^n` is an error ("constant ASH
      count out of range" / "result too large") - the same boundaries as
      voc's error 208, probed at 62/63, -62/-63, `ASH(3, 62)`, `ASH(MAX(
      HUGEINT), 1)` - and a right shift floors. The type is the wider of
      LONGINT and `x`'s, *and no narrower than the value needs*: voc types
      `ASH(1, 40)` a LONGINT under `-O2` and silently keeps 32 bits (0),
      where poc makes it a HUGEINT, so assigning it to a LONGINT is a
      compile-time error (`semantic-reject-const-ash-too-wide`; under `-OC`
      it is fine, `oc-flag-const-ash-fits-longint`). Like voc, and unlike
      `+`, the result is not re-typed *downward*: `ASH(1, 3)` stays a
      LONGINT. The other value-argument functions are not folded (Phase
      11 step 2), though `IsConstantExpr`/`EvaluateDesignator` now have the
      shape each would be one case of.
    - *`CONST` `MAX`/`MIN` of `REAL` and `LONGREAL`* (`MaxMinBound`): IEEE
      754's largest finite value and its negation, built from powers of two
      (`MaxReal` = 2^128 - 2^104, `MaxLongReal` = 2 * (2^1023 - 2^970), both
      exact) since voc rejects the literals. `GenerateMaxMin` now takes every
      type from `MaxMinBound` and `RealConstant` writes the value's bit
      pattern (`0x47EFFFFFE0000000`, `0x7FEFFFFFFFFFFFFF`), so the constant
      and the run-time form cannot differ. The value written to a `.sym`:
      `ConstantEvaluator.ParseReal` cannot read `1.7976931348623157D308`
      back exactly (308 multiplications by ten drift), so tier 2 of the real
      exporter fails for it; `ModuleInterface.ExtremeRealSpelling` prints a
      value that is exactly the largest finite one of its own type, or its
      negation, as `MAX(LONGREAL)`, `MIN(REAL)` and so on, which the reader
      folds back exactly (`module-interface-const-fold`, `-O2` and `-OC`,
      with the interface read back as source and required to reproduce
      itself). *Not fixed*: any other computed real of extreme magnitude
      (`MAX(LONGREAL) / 2`, `1.0D300 * 1.5`) still cannot be exported, for
      the same reason - it was so before this step; Phase 11 step 2 has it.
      A folded integer prints as its value, so its type after a `.sym`
      round trip is the minimal one (`ASH(1, 3)` is a SHORTINT to an
      importer, a LONGINT at home); every other constant already worked so.
    - *Fixtures* (174 pass): `semantic-const-fold-integer` (accepted, voc-
      clean), `semantic-reject-const-fold-narrow` (nine assignments, each
      rejected by voc too), `semantic-reject-const-fold-overflow` (every
      error class, in `CONST` and in statements), `semantic-reject-const-
      quotient-overflow`, `semantic-reject-const-ash-too-wide`, `oc-flag-
      const-ash-fits-longint`, `module-interface-const-fold`, `llvm-const-
      fold` (52 checks, 50 of them cross-checked under voc - the rest are
      poc-only: voc's `MAX(REAL)` reaches the C compiler at 8 digits and
      its `MAX(LONGREAL)` is low by design), `llvm-const-fold-import` (the
      constants through a `.sym`), `llvm-const-fold-ir` (`-O2` and `-OC`
      goldens), and both new run fixtures in `llvm-i686-runtime`. Three
      existing IR goldens changed only by folding (`llvm-predeclared-ir`,
      `llvm-system-ir`, `llvm-straight-line-arithmetic`); the last one's
      `(-7) DIV 2` is now `minusSeven DIV 2` on a variable, so its floored
      DIV/MOD code is still generated and checked.
    - *The step 9 sweep after this step*: the whole suite passes on Linux at
      both word sizes (64-bit, and the 32-bit `i686` runs in `llvm-i686-
      runtime`). **Not run: any BSD** - the BSD hosts were unreachable this
      session - so Phase 9 is not yet done by its own criterion; Phase 11
      step 8 carries the outstanding BSD runs.

**Testing summary**: golden-`.ll`-diff fixtures for the purely static
pieces (step 1, and step 4a's `.sym` writer/checker fixtures plus its one
cross-module descriptor golden), promoted to compile+link+run+diff everywhere else,
matching Phase 8's own testing posture — culminating in step 9's
whole-suite/whole-platform-matrix gate, re-run once step 10 (Catching Up)
has added its own fixtures. Self-hosting is Phase 10's own
exit gate, not this phase's.

### Phase 10 — LLVM runtime library (voc-compatibility + Oakwood + Appendix C) + self-hosting

**Goal**: a real `rtl/llvm` module set, built as genuine Oberon-2 source
compiled by poc itself (not hand-written IR), covering (a) every voc
module poc's *own* front end/backend/driver source currently imports —
confirmed by grepping every `IMPORT` in `src/` for a non-`poc`-own
module name: `Out` (`Diagnostics.Mod`), and `Modules`, `Files`, `Out`,
`Platform` (`Poc.Mod`); `ModuleInterface.Mod`/`LLVMToolchainDriver.Mod`
also import `Files`/`Platform` — and (b) the Oakwood Guidelines' own
"basic" library modules (`In`, `Out`, `Files`, `Strings`, `Math`,
`MathL` — see below for `XYplane`/`Input`, the two basic modules this
phase deliberately excludes). Also covers (c) `SYSTEM` (Appendix C):
unlike (a)/(b), not a real `.mod` source file (`SYSTEM` has no body in
any Oberon-2 implementation — every procedure it exports is compiler
magic, the same way `PredeclaredProcedures.Mod`'s ordinary ~20 names
are), but grouped into this phase rather than Phase 13 because it's the
same kind of "give the LLVM backend a capability it has never had"
work as (a)/(b), and because `AGENTS.md`'s own "Appendix C" section has
flagged it as genuinely unscheduled ("no phase has scheduled it") since
before this file described any phase past 9 — see step 7 below. This
phase exists because Phase 9's own exit gate never needed real formatted
I/O, file access, or raw memory access — every Phase 8/9 fixture prints
via a direct `SysWrite` FFI declaration — but poc's own source genuinely
needs (a), and self-hosting (this phase's own final step) cannot get
off the ground without it.

**Why this is its own phase, not folded into Phase 9 or deferred to
"later, as fixtures need it"** (this file's own "Decisions locked in"
table's original phrasing): the concrete list above came directly from
grepping poc's own source, at the user's explicit request, rather than
being assumed — and one real, load-bearing dependency fell out of doing
that for real rather than guessing: voc's own `Files.Mod` (confirmed by
reading `src/runtime/Files.Mod` in voc's own source tree) represents an
open file as `File* = POINTER TO FileDesc`, so even a from-scratch
`rtl/llvm/Files.Mod` needs real `POINTER`/`NEW`/GC to allocate one — Phase
9's own step 4/5 work, not something this phase can build around. Since
self-hosting additionally requires every *language* feature poc's own
source uses (which, being a fairly ordinary Oberon-2 compiler built
from heap-allocated, pointer-linked `Desc` records throughout
`SyntaxTree.Mod`/`SymbolTable.Mod`/`Types.Mod`, is effectively "most of
Phase 9"), self-hosting genuinely cannot happen before Phase 9's own
full-parity gate — hence this phase sitting immediately after it, with
its own bootstrap step as its capstone, not Phase 9's.

**Explicit non-goals**: `XYplane` (elementary pixel-plane graphics) and
`Input` (mouse/keyboard/clock access) are two of the Oakwood Guidelines'
own eight "basic" modules but presuppose a windowed/interactive
environment poc's own headless, batch, command-line target has no
equivalent of at all — voc itself only provides them under its
GUI-hosted `v4`/`oocX11` library personalities, never for the plain Unix
batch-compiler personality this project has followed since the
"Decisions locked in" table's own "Vishap Oberon, used two ways"
framing. `Coroutines`, `MathC`, `MathLC` are the Guidelines' own
"Additional Modules" — explicitly optional, "provided... on an 'as
needed' basis" — and nothing here needs non-preemptive threads or
`COMPLEX`/`LONGCOMPLEX` arithmetic (poc doesn't even support those as
types). `Texts.Mod`/`Oberon.Mod`/the interactive-environment modules
Appendix D itself describes (commands, dynamic loading, the browser) are
superseded here by the Oakwood Guidelines' own more portable `In`/`Out`
for the same reason the Guidelines exist in the first place — avoiding
baking in ETH Oberon System GUI-environment assumptions.

**Proposed build order** — each numbered step lands its own conformance
fixtures before the next starts, matching Phase 8/9's own incremental
style exactly. Every step here builds on Phase 9's `POINTER`/`NEW`/GC
work already being in place.

1. **`Console.Mod`.** `String(s: ARRAY OF CHAR)`/`Ln` (voc's own names, not
   the `PrintString`/`PrintLn` this step first proposed - so a program using
   them runs under both compilers), wrapping
   the same `write(2)` FFI call every Phase 8/9 fixture already declares
   inline, but as genuine Oberon-2 source compiled by poc and `IMPORT`ed
   by a small new fixture — proves the self-hosted-rtl-module mechanism
   for the first time (ordinary procedure-with-body codegen, Phase 8
   step 10, plus general multi-module `IMPORT`, Phase 8 step 12, working
   together on a *library* module, not just two peer user modules the
   way `llvm-multi-module` exercised it). Existing fixtures are not
   required to migrate off their own direct `SysWrite` declarations (low
   value, high busywork); new fixtures from step 2 onward should prefer
   `Console.Mod` where it's a natural fit. Not one of poc's own source
   dependencies (confirmed by the `IMPORT` grep above), but still built
   first: it's the smallest possible real rtl module, and every later
   step in this phase needs the same mechanism proven to work.
   **Testing**: one fixture (`llvm-console`, compile+link+run+diff-stdout)
   proving `Console.String`/`Console.Ln` end-to-end.
   **Implemented (2026-09-19)**: `rtl/llvm/Console.Mod` has voc's
   `Console` interface minus its input half - `Flush`, `Char`, `String`,
   `Int(i, n)`, `Ln`, `Bool`, `Hex` (`Read`/`ReadLine` belong to step 5's
   `In`). Decisions, probed against voc's `src/library/v4/Console.Mod`:
   - **Unbuffered**: voc line-buffers (128 characters, flushed at each
     newline) and, by its source, never flushes at exit, so output without
     a final `Ln` would be lost. Here every call writes before it returns, so nothing is lost
     to a trap or a plain end of program and it interleaves with other
     writers of descriptor 1; `Flush` is empty, kept for compatibility.
   - **One external `write(2)`**, declared `(descriptor: LONGINT; buffer,
     count: SYSTEM.ADDRESS)` with no result - the backend declares a C
     symbol once per program (first declaring module wins) and its trap
     support calls `write` as a `void` function, so a `Console` `write`
     returning a value would mismatch it. The price: a short write is not
     noticed. The count is `SYSTEM.ADDRESS`, `size_t`-wide, so it is right
     on i686 too (the older fixtures' `HUGEINT` count is passed as two words
     there, which works only because the low one comes first).
   - **`Int(i: HUGEINT; n: LONGINT)`** where voc's takes `SYSTEM.INT64`
     (poc has none yet; `HUGEINT` widens from every integer type). voc's
     goes through a `LONGINT`, so a value beyond it prints wrong (under
     `-O2`, `MAX(HUGEINT)` prints `1`) and it prints a fixed wrong string
     for the smallest one (read from its source, not run; its own "todo.
     support int64 properly"); poc's prints them right. The smallest `HUGEINT` is written whole,
     having no positive counterpart to print digit by digit. Padding is
     written as one write per 32 blanks, then the digits in one write.
   - **`Hex(i: LONGINT)`** prints two digits per byte of a `LONGINT`
     (8 under `-O2`), as voc's does.
   **Testing**: `llvm-console` (compile+link+run, and its output must equal
   what voc's own `Console` prints for the same source, checked in
   `test.sh` - voc runs first because poc leaves `Console.sym` in the
   working directory, which voc would find and reject); `llvm-console-extra`
   (poc only: `HUGEINT` beyond `LONGINT`, an unterminated `ARRAY OF CHAR`,
   and a program that imports `Console` while declaring `write` itself);
   both also run as i686 executables in `llvm-i686-runtime`. 176 pass.

2. **`Platform.Mod`.** The voc-only, non-Oakwood extension module poc's
   own driver depends on directly: `Chdir`/`CWD` (import-path/output-
   directory resolution), `GetEnv` (toolchain/environment lookup),
   `PID` (unique temp-file naming), `Unlink` (temp-file cleanup), and
   `System(cmd: ARRAY OF CHAR): INTEGER` — the exact mechanism a
   self-hosted `LLVMToolchainDriver.Mod` needs to shell out to `clang`/
   `llc` the same way it does today (voc's own real signature, confirmed
   by reading `src/runtime/Platformunix.Mod` in voc's own source tree).
   Every one of these is a thin wrapper over a `["C"]`-declared libc
   call (`chdir`, `getcwd`, `getenv`, `getpid`, `system`, `unlink`) —
   no allocation needed, the simplest step in this phase after
   `Console.Mod`.
   **Testing**: a fixture exercising `System` (run a trivial shell
   command, check its exit status) and `GetEnv`/`Unlink`/`Chdir`/`CWD`
   round-tripping a real environment variable and a real temp file.
   **Implemented (2026-09-19)**: `rtl/llvm/Platform.Mod` has exactly the
   six named above plus the `ErrorCode` type, with voc's own signatures
   (`Chdir(VAR n: ARRAY OF CHAR): ErrorCode`, `GetEnv(var: ARRAY OF CHAR;
   VAR val: ARRAY OF CHAR)`, `System(cmd: ARRAY OF CHAR): INTEGER`,
   `Unlink(VAR n): ErrorCode`, `PID-: INTEGER`, `CWD-: ARRAY 256 OF
   CHAR`) so poc's source compiles against either module. Not brought
   over: voc's file-handle, clock, signal and error-classification
   procedures - step 3's `Files.Mod` will add whatever it needs. Decisions,
   read from voc's `Platformunix.Mod`:
   - **An error is -1, not errno.** voc returns the errno value. The
     portable way to read it does not exist: `errno` is reached through
     `__errno_location` on Linux, `__error` on FreeBSD and `__errno` on
     NetBSD and OpenBSD, and an external declaration of a symbol the
     system lacks fails to link, with no conditional compilation to choose
     between them. Nothing in poc's source looks at more than `= 0`
     (the one place that mentions a code, `ModuleInterface.Write*`'s
     comment, only says what it happened to be). If a later module needs
     the reason, the fix is per-system - a small C shim, or a build-time
     choice - and belongs to Phase 11.
   - **`PID` is never negative.** voc keeps it in an `INTEGER`, so under
     its 16-bit `-O2` model a pid above 32767 wraps, possibly to a
     negative number, which `LLVMToolchainDriver.AppendInt` (documented as
     taking a non-negative number) would print wrongly. Here a pid that
     does not fit is reduced modulo 2^15 (one that fits is left whole,
     under a 32-bit `INTEGER` all of them).
   - **Strings must end in `0X` inside their array**: a `Chdir`, `Unlink`
     or `System` argument that does not is refused (-1) and a `GetEnv`
     name that does not finds nothing, instead of running `getenv`/`chdir`
     off the end of the array.
   - **`System` returns the raw wait status**, exit code times 256, as voc
     does, narrowed to `INTEGER` - `exit 255` (65280) wraps to -256,
     nonzero, which is all poc's own caller tests.
   - **C `int` is written `LONGINT`** in the external declarations, right
     under the `-O2` model poc generates code for, wrong under `-OC` (a
     64-bit `LONGINT` reads a return register's upper half, which the
     ABI leaves undefined). Step 7's `SYSTEM.INT32` is only an alias of
     `LONGINT` (the `-O2` width), so it is *not* the size-model-independent
     spelling this needed and the move was not made; step 8's self-hosting
     under the `-OC` model needs a real fixed-width `INT32` (Phase 11 table)
     and these declarations, and `Console`'s `write`, moved to it.
   **Testing**: `llvm-platform` (25 checks over `GetEnv` - a set, an empty,
   an unset and a truncated variable; `System`'s status; `Unlink` of a real
   file twice; `Chdir` into a real directory and back, seen from the
   shell a `System` call starts and from `CWD`, and a failing one - run
   under poc and voc, which must print the same; `test.sh` exports the
   variables and builds the directory, and, as for `Console`, runs voc first
   because poc leaves `Platform.sym` in the working directory); `llvm-platform-extra`
   (poc only: `PID` against the shell's own `$PPID`, `-1` as the failure
   code, unterminated strings), also run as an i686 executable in
   `llvm-i686-runtime` (`llvm-platform` needs its environment and
   directory, which that harness does not set up). 178 pass.

3. **`Files.Mod`.** The subset poc's own source actually calls (again
   confirmed by grep, not assumed): `File`, `Rider`, `New`, `Old`,
   `Register`, `Close`, `Length`, `Set`, `Write`, `WriteString`,
   `ReadLine`, `ReadString` — enough for `ModuleInterface.Mod` to read/
   write `.sym` files and `LLVMToolchainDriver.Mod` to read/write `.ll`
   files once self-hosted. `File* = POINTER TO FileDesc` (matching voc's
   own representation) is why this step comes after Phase 9's GC, not
   before it; the underlying bytes move through `["C"]`-declared
   `open`/`read`/`write`/`close`/`lseek`. This module happens to also be
   one of the Oakwood Guidelines' own eight "basic" modules, so building
   it against poc's own concrete usage automatically covers most of the
   Guidelines' own `Files` interface too, not just poc's narrower slice.
   **Testing**: a fixture that creates a file, writes through a
   `Rider`, closes it, reopens it, and reads the same bytes back via
   `ReadString`/`ReadLine`.
   **Implemented (2026-09-20)**: `rtl/llvm/Files.Mod` has the twelve
   procedures above plus `Read`, `Pos`, `Base`, `Delete` and `Rename`, with
   voc's signatures except that `Read`/`Write` take a `CHAR` where voc's
   take `SYSTEM.BYTE` (step 7). Not brought over: `ReadBytes`/`WriteBytes`
   (need `BYTE` too), the typed `ReadInt`/`WriteReal`/... family, `Purge`,
   `GetDate`, `GetName`, `SetSearchPath`. `File` is
   `POINTER TO FileDesc` as planned, so the module needs `NEW` and the
   collector. The Oakwood interface is therefore *not* mostly covered, as
   this step expected: what poc calls is a small slice, and the rest is
   Phase 11's if wanted. Decisions, read from voc's `Files.Mod`:
   - **stdio, not `open`/`lseek`, as planned.** The bytes move through
     `fopen`/`fread`/`fwrite`/`fseek`/`fclose`/`rename`. `open(2)` takes
     flag bits that differ between Linux and the BSDs (`O_CREAT` is 0x40 on
     Linux and 0x200 on the BSDs, `O_TRUNC` 0x200 and 0x400), and `lseek`'s
     `off_t` is 32 bits on 32-bit Linux and 64 on 32-bit NetBSD, OpenBSD
     and FreeBSD, so an external declaration right for one is wrong for
     another, and there is no conditional compilation to pick. stdio has a
     mode *string* and a `long` offset, a word on all of them. (The BSD
     values are from memory: to be confirmed on the BSD hosts.) The
     `i686` run of both fixtures below passes with the 32-bit `long`.
   - **No buffers of its own** - voc keeps four 4 KB buffers per file and
     a table of open files, to share them between `File`s of one OS file,
     and a `Deregister` that moves an open file out of the way; libc's
     buffering replaces the first and Unix's `rename` semantics the third.
     A `File` is a stream, a length and a position; a `Rider` is a
     position. The operations seek when the stream is somewhere else or was
     last used the other way.
   - **`New` writes to a temporary file** (`.tmp.<n>.<pid>` beside the
     final name, created at the first write) and `Register` renames it, so
     a registered file replaces the old one in one step and never appears
     half written; voc does the same once it has more than four buffers
     of data, and writes directly otherwise. Names are made absolute
     when given, so a `Chdir` between `New` and `Register` does no harm
     (by its source, voc renames its absolute temporary name onto the
     relative final one, i.e. into the wrong directory).
   - **`Close` closes the stream**, and the `File` reopens itself if used
     again. Nothing here finalizes a `File` (the collector has no
     finalizers), so this is what keeps a program from running out of
     descriptors; a dropped `File` still keeps its stream until the
     program ends.
   - **Failures**: `Old` gives `NIL` for a missing file, an empty or too
     long name, or a directory (which `fopen` accepts for reading on
     Linux; a one-byte probe read finds it). What cannot be reported - a
     file that cannot be created, a write that fails - prints
     `-- <what>: <name>` and stops with `Halt(99)`, as voc does.
   - **Where voc differs and poc does not follow**: two `Old` calls for one
     file give two independent `File`s (voc shares one); `ReadString`/
     `ReadLine` cut an over-long value short where voc overruns the array;
     files are limited to a `LONGINT`'s range (voc's too under `-O2`).
   - **voc quirks met while cross-checking**: `Rename` or `Delete` of a
     file that this process has open as a `File` makes voc rename it to a
     temporary name first, so, apparently, `Delete` fails (errcode 2)
     and `Rename` halts ("Couldn't rename previous version of file being
     registered"); the shared fixture only renames and deletes files it has not
     opened, and looks at the result with the shell.
   **Testing**: `llvm-files` (37 checks: a new file's length as it grows,
   register, reopen, `ReadString`, `ReadLine` over LF, CR LF, empty and
   unterminated lines, `Set` clamping, overwriting and extending, a
   20000-byte file probed at the 4096-byte block boundaries voc uses, two
   riders on one file, `Old` of nothing, registering over a file, use
   after `Close`, `Delete`/`Rename` - run under poc and voc, which must
   print the same); `llvm-files-extra` (19 checks, poc only: values cut
   short, the temporary file and where it lives, `Chdir` between `New`
   and `Register`, a directory and a 300-character name given to `Old`,
   2500 opens in a row with `Close`, failures being -1); `llvm-files-fail`
   (an uncreatable file: message and exit status 99). `llvm-files` and
   `llvm-files-extra` also run as i686 executables in `llvm-i686-runtime`.
   181 pass. **Checked against poc's own source**: `poc -emit-llvm-ir` of
   `ModuleInterface.Mod`, the heaviest user of `Files`/`Platform`, with the
   whole front end below it and a throwaway `Out` standing in for step
   5's, compiles against these two modules. `LLVMToolchainDriver.Mod` does
   not get that far, for a reason that has nothing to do with them:
   poc's checker rejects poc's own `SemanticActions.Mod` (29 x "guarded
   pointer variable may be manipulated by non-local operations", the
   `WITH` rule that `CheckWithGuard` applies more strictly than voc
   does).

   **Settled (2026-09-20, step 8): `CheckWithGuard` now matches voc's real
   rule exactly, not just more closely.** The 29 rejections were plain
   type-case dispatches in poc's own source (`WITH node: ...ArrayTypeNode
   DO`, `WITH sel: ...FieldSelector DO`, and the like) over an ordinary,
   non-`VAR` local - never genuinely reachable from another procedure by
   Oberon-2's own scoping rules, only flagged because `CollectProcAssigned
   Names`'s original whole-module pre-pass matched by bare name text with
   no notion of which procedure declared which variable, and `node`/`sel`/
   `s` are used constantly across this file. Probed voc directly (six
   standalone repros, `/tmp/vocwg/vocwg1..6.mod`) rather than trusting the
   header comment's own account from memory, and found voc's real rule is
   both simpler and more precise than what poc had approximated: a local
   may be reassigned by bare name *anywhere at all in its own declaring
   procedure*, including textually inside the very guarded branch (voc
   accepts that directly - no statement-order or reachability distinction
   is drawn within the declaring procedure itself); only a reassignment
   inside a procedure *nested inside* the declaring one (any depth) is
   rejected; an unrelated procedure's own same-named-but-different local
   never interacts at all (voc resolves by declared identity, never text).
   New `SymbolTable.ScopeDesc.enclosingProc` (set at every procedure's own
   body scope, top-level or nested, and carried through any scope opened
   another way - a `WITH`'s own narrowed scope) gives `CheckWithGuard` this
   distinction for free: a global still uses the whole-module scan
   (genuinely reachable from anywhere), a local uses a scan of just its
   declaring procedure's own *nested* procedures (never its own direct
   statements). Re-verified against all six voc repros: exact agreement.
   `SemanticActions.Mod` now checks clean under real `poc -check`.

   **Every front-end/backend/driver file checks clean under `poc -check
   -OC` (2026-09-20).** Pushing on past `SemanticActions.Mod` hit what
   looked like a second, genuine blocker: `LLVMCodeGenerator.DoubleBitsText`
   declares `mantissa: LONGINT` and assigns it `2251799813685248` (2^51,
   the quiet-NaN bit) - too wide for a 32-bit `LONGINT`, so poc's own
   minimal-integer-literal-type rule types the numeral `HUGEINT` and
   correctly rejects the assignment under poc's *default* `-O2` model.
   This turned out not to be missing functionality at all: `Poc.Mod`
   already has real `-O2`/`-OC` flags (`ConstantEvaluator.SetSizeModel*`,
   built in Phase 9 step 10 for `MAX`/`MIN`/`SIZE` constant folding) -
   this session's own self-check commands simply weren't passing `-OC`,
   the same flag `tools/bootstrap/stage0` already builds poc's own source
   with (its own header comment already says why: `Types.Value.intVal`
   needs a real 8-byte host `LONGINT` to hold a full-range `HUGEINT`
   constant). Re-running every front-end file, every `rtl/llvm` module
   poc's own source imports, both backend files and `src/driver/Poc.Mod`
   itself through `poc -check -OC` (not just `-emit-interface`, so every
   procedure body is checked, not just signatures) - all clean, zero
   errors. `Poc.Mod` compiling clean under its own checker is real
   evidence Stage 1 *type-checking* is unblocked.

   **A real `poc -build`/`-emit-llvm-ir` attempt on the whole program found
   two genuine codegen bugs, both the same class, both fixed (2026-09-20).**
   `poc -build src/driver/Poc.Mod` (whole program, `-OC`) crashed `poc`
   itself with an opaque `Terminated by Halt(-2). Index out of range.` -
   poc's own array-bounds check, working as designed, catching an
   out-of-bounds write rather than corrupting memory, but with no stack
   trace to say where. Isolated with temporary `Out.String` progress
   prints in `GenerateProcedureDecl` (rebuilt via Stage 0 after each
   change) plus bisection on scratch copies of the real source (neuter a
   suspect procedure's body down to nothing, confirm the crash disappears,
   restore statements one at a time) - the standard technique this session
   used earlier for the `WITH`-guard bug, reapplied here twice:
   - **`LLVMTypes.TypeString`'s recursive struct-type-string builder had no
     bounds check** against its `VAR result: ARRAY OF CHAR` destination -
     fine for every fixture built so far (all short, hand-written test
     programs), but poc's own `Parser` record (`src/front/Parser.Mod`) -
     an ordinary three-field record, nothing exotic - built a struct type
     string over 64 characters once nested, overflowing the 64-character
     `ValueText` buffer essentially every call site passed. Minimal repro:
     a `VAR` parameter of a record type containing a nested pointer-
     bearing sub-record, a plain non-pointer middle field, and a second
     direct pointer field, with a same-typed local declared - `/tmp/wgtest`
     and `/tmp/recbug`'s `rb4`..`rb12` narrowed this down live. Fixed: a
     new `LLVMTypes.typeStringLength*` (799, comfortably larger than any
     record type this project's own source produces - see its own header
     comment for the full account) replaces the internal 256-character
     buffers in `RecordTypeString`/`ArrayTypeString`, and `Value.llvmType`
     plus every other `LLVMCodeGenerator.Mod` local/field that receives an
     arbitrary (not hardcoded-basic) type's string - `EmitGlobals`,
     `BindLocalVars`, `BindFormalParams`, `ParamLLVMType`, pointer-
     dereference/guard/narrowing sites, function-result-type sites - moved
     from `ValueText` (64) to the existing `LongText` (800). Purely
     numeric-only sites (`GenerateDivMod`, relational ops, `SHORT`/`ASH`,
     `SET` operations, `CASE` label widening) were left alone: Appendix A
     restricts those operators to basic types, so a record type can never
     reach them - confirmed by reasoning about the report's own rules, not
     assumed.
   - **A second, different instance same class, found by pushing on past
     the first fix**: `GenerateNew`'s own `tagText: ValueText` wraps the
     already-`LongText`-sized `longTag` (a type's full `ptrtoint (ptr
     @Module.Type.tag to iN)` operand) in a second buffer sized like the
     first bug's - safe for any external test fixture's short module name,
     but `LLVMCodeGenerator.Mod` compiling *itself* embeds its own 18-
     character module name in every symbol it generates for its own
     types, pushing `NEW` of one of its own record types (`DeclaredExternal
     Desc`, found processing `MarkDeclaredExternal`) over 64 characters.
     Fixed the same way: `tagText` moved to `LongText`. `QualifiedName`/
     `ModuleQualifiedName` use the identical pattern but were checked and
     left alone - poc's own longest procedure name (`InitImportPath
     FromEnvironment`, 29 characters) plus its longest module name
     (`LLVMToolchainDriver`, 19) stays well under 64, confirmed by grepping
     every declared procedure name in the project, not assumed safe.
     `make test` (198) clean after each fix; both verified by re-running
     the exact triggering `-emit-llvm-ir` command on the real file.

   Past both fixes, `poc -build` on the whole program gets measurably
   further: `poc` itself no longer crashes, and `clang` now rejects the
   generated `Poc.ll` outright - `%t26751 = call ptr
   @SemanticActions.NewQualidentType([256 x i8] 0, [256 x i8] 0, i32
   %t26749, i32 %t26750)`, an integer literal `0` where an `[256 x i8]`
   array constant belongs.

   **A third bug, a real gap rather than a buffer size, found and fixed
   (2026-09-20): passing a string literal to a *value* `ARRAY OF CHAR`
   parameter (Oberon2.pdf Appendix A rule 3 - AGENTS.md's own language-
   spec notes) never had real codegen at all.** `EvaluateCallArg`'s plain
   (non-`VAR`, non-open-array) branch always routed through `GenerateExpr`/
   `GenerateLiteral`, whose own header comment already documented the
   invariant it silently violated here: "a string in a character-sequence
   position ... never comes through GenerateExpr at all" - true for
   assignment, COPY and comparisons, each with their own dedicated path,
   but never actually enforced for a call argument. An empty string hit
   `GenerateLiteral`'s own "empty string literal in a scalar position"
   placeholder (a bare `0`, meant for genuinely unsupported shapes);
   poc's own `Parser.Mod` calling `SemanticActions.NewQualidentType("", "",
   ...)` - two 256-character `SyntaxTree.Ident` value parameters - is the
   real repro. Fixed with a new `GenerateCallArgList`-level special case
   (`AppendStringLiteralArrayConstant`, `AppendChar`/`AppendEscapedByte`)
   that builds a real `[N x i8] c"..."` LLVM array constant directly -
   bypassing `EvaluateCallArg`/`Value` entirely, since the escaped text
   (the array's own unwritten tail zero-padded byte by byte, three
   characters per `\XX` escape) runs well past `Value.text`'s own
   `ValueText` bound for any real fixed array, and widening `Value.text`
   itself turned out far too invasive (17 existing `:=` assignment sites
   broke, reverted). A second problem surfaced immediately after fixing
   the first, live against poc's own source rather than a hand-written
   repro: `GenerateCallArgList`'s own accumulated `text` buffer (`LongText`,
   800 characters) comfortably holds *one* such constant (782 characters
   for a 256-length array) but not `NewQualidentType`'s own *two* in one
   call (~1564 characters together, before the trailing `INTEGER`
   arguments) - `AppendStringLiteralArrayConstant`'s own defensive bound
   check (against the room actually *left* in the buffer, not the buffer's
   total declared size - an earlier version of the check missed this and
   still passed every hand-written repro, which never happened to chain
   two such arguments in one call) correctly refused the second one and
   fell back to the old, still-broken path, which then overflowed the
   now-nearly-full 800-character buffer for real, tripping the exact same
   index-range trap as the first two bugs. Fixed with a new, dedicated
   `ArgsText` (4096 characters, comfortably holds several such arguments
   at once) replacing `LongText` for every `GenerateCallArgList`-facing
   `argsText`/`receiverText` variable - `AppendStringLiteralArrayConstant`
   itself needed no change, since its own bound check already reads the
   buffer's real size via `LEN(text)`. Both steps isolated the same way as
   the earlier two bugs: temporary `Out.String` progress prints (this time
   inside `EvaluateCallArg`/`AppendStringLiteralArrayConstant` themselves,
   not just `GenerateProcedureDecl`), rebuilt via Stage 0 and re-run
   against the real file each time, removed once each fix was confirmed.
   `make test` (198) clean throughout.

   **Stage 1 reached (2026-09-20): `poc -build src/driver/Poc.Mod`, using
   `poc` itself, produces a real, working executable.** `poc-stage1` runs
   (`poc-stage1 -check-syntax ...` succeeds against real source) - the
   first time poc has ever compiled itself into a working binary, not just
   type-checked its own source.

   **Stage 2 and the fixed point reached (2026-09-20).** `poc-stage1` first
   trapped at run time with "no matching WITH guard" (exit 6), on any
   module with a module-level `VAR`. `gdb -batch -ex 'break exit' -ex run
   -ex bt` on the Stage 1 binary named the procedure at once
   (`LLVMCodeGenerator.CollectRecordTypes`; the binary keeps its symbols) -
   quicker than the print-and-bisect method the three earlier bugs needed,
   since a poc-built program, unlike a voc-built one, is an ordinary native
   executable. The cause was not a logic gap in that procedure: its `WITH`
   ends in an explicit empty `ELSE END`, which parses to a NIL `elseBody`
   exactly like no `ELSE` at all, and `GenerateWithStatement` chose
   trap-versus-fall-through by `s.elseBody # NIL`. The same ambiguity had
   been fixed for `CASE` in Phase 8 (`hasElse`); `WITH` never got the
   flag. Fixed the same way: `WithStatementNodeDesc.hasElse`, set by
   `Parser.Mod`, passed through `SemanticActions.NewWithStatement`, tested
   by `GenerateWithStatement`. poc's own source is full of `ELSE END`
   `WITH`s (a `WITH` used only to pick out what to do next, falling through
   for any other node), so every one that fell through trapped, and no
   existing fixture had one. New fixture `llvm-with-empty-else` (fails
   without the fix, with the trap; 199 fixtures now).

   With that, Stage 2 builds, and a third generation from it too. The
   whole-program `Poc.ll` (3.6 MB), every generated `.sym` and the
   executable are byte for byte identical across Stage 1, Stage 2 and
   Stage 3 - nothing in them carries a timestamp or a path, so no "modulo"
   was needed. The full conformance suite passes under the Stage 1 binary
   (199/199, `POC_BIN_DIR` pointing at it) as it does under Stage 0's.
   `tools/bootstrap/stage1` and `stage2` (the latter does the comparison
   and exits non-zero on any difference), and `make stage1`/`make stage2`,
   are the scripts this step promised.

   **BSD-verified (2026-09-20), and a real, NetBSD-only bug found and
   fixed along the way.** All 23 of Phase 10 steps 1-7's runnable rtl
   fixtures (`llvm-console` through `llvm-system-shifts`, the full list
   in "SYSTEM subset" and this step and steps 1/2/4-7's own "Testing"
   entries) were cross-compiled with `-target i386-unknown-openbsd7.9`/
   `-target x86_64-unknown-netbsd10.0`, copied to `erekose`/`terhali`
   (see "Vishap Oberon"/[[reference-bsd-test-hosts]]), and built+run there
   with each machine's own native `clang`, same method as Phase 8 step
   13's original sweep. First pass: 23/23 on erekose, 22/23 on terhali -
   `llvm-files-extra` check 14 (`Files.Old` of a directory name must be
   `NIL`) failed there. Root cause, confirmed with a standalone C probe
   run on both machines: `Old`'s directory rejection (the `Readable`
   procedure above) relies on a one-byte `fread` of an `fopen`'d directory
   failing - true on Linux and OpenBSD (`count=0`, `ferror=1`), but
   NetBSD's libc lets that `fread` succeed (`count=1`, `ferror=0`) - an
   old BSD allowance for reading raw bytes off a directory stream that
   Linux and OpenBSD's libc no longer honor, not a poc bug in the usual
   sense. Fixed with a new `IsDirectory` check ahead of the `fopen` path,
   using `opendir`/`closedir` instead of the `fread` probe - POSIX
   `opendir` succeeds only for a directory, confirmed identically on
   Linux, OpenBSD and NetBSD (no FreeBSD host to check against yet).
   `Readable` is kept as a second guard for whatever else might open but
   not read. Re-run after the fix: 23/23 on both erekose and terhali, and
   `make test` (198, unchanged) still clean on Linux. The O_CREAT/
   O_TRUNC/off_t values mentioned above remain unconfirmed on the BSDs -
   moot, since `Files.Mod` never calls `open`/`lseek` at all, only stdio.

4. **`Modules.Mod`.** `ArgCount-` (a read-only exported `VAR`, set once
   at process start) and `GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR)` —
   command-line argument access, the second concrete example the user
   asked for. Real dynamic module loading (Appendix D2's own sense of
   "Modules") is explicitly out of scope — poc only ever needs the
   argv-access half of what voc bundles under this one module name,
   matching voc's own real `src/runtime/Modules.Mod`, confirmed by
   reading it directly rather than assuming the name implies loader
   semantics here too.
   **Testing**: a fixture that echoes its own `ArgCount`/`GetArg` values
   back, run with a fixed, known argument list from `test.sh`.
   **Implemented (2026-09-20)**: `rtl/llvm/Modules.Mod` has `ArgCount-`,
   `GetArg`, and from voc's module also `ArgVector-`, `GetIntArg` and
   `ArgPos` (the same kind of thing, a few lines each). Not brought over:
   voc's module list and command loading (`ThisMod`, `ThisCommand`,
   `Free`), `BinaryDir` and `MainStackFrame`. The piece that was not just a
   library module: **the program's `main` had no arguments**, so there was
   nothing to read. `LLVMCodeGenerator.GenerateProgram` now emits `define
   i32 @main(i32 %argc, ptr %argv)` for a program that contains a module
   named `Modules`, and its first act is `Modules.Init(argc, argv)` (both
   as words, sign-extended on a 64-bit target), before any module body, the
   same pattern as the collector's stack base. A program without `Modules`
   keeps the argument-less `main`, so no other IR changes. (A user module
   that is itself called `Modules` would get the call too - the same hazard
   as `GarbageCollectedHeap`.) Decisions:
   - **`GetArg` out of range gives `""`**; voc leaves the value as it was,
     so a caller that ignores `ArgCount` reads the previous argument again.
   - **The address of argument `n` is computed in `LONGINT`**: `n *
     SIZE(SYSTEM.ADDRESS)` in `INTEGER` arithmetic wraps at 4096 arguments
     under the 16-bit `-O2` model, and a command line may hold more (voc's C
     promotes to `int`, so presumably it does not have the problem).
   **Testing**: `llvm-modules` (10 checks and a listing, run under poc and
   voc with the arguments `alpha "two words" "" 42 -7`, output equal;
   argument 0, the program's name, is only checked to be there);
   `llvm-modules-extra` (poc only: out-of-range numbers, a 3000-character
   argument, cut to 15 characters or read whole); `llvm-modules-ir` (golden
   `main` for x86_64 and i686); `llvm-modules` also runs as an i686
   executable in `llvm-i686-runtime`, whose `check` now takes the
   arguments to start a program with. 184 pass.

5. **`Out.Mod`/`In.Mod` (Oakwood's own basic pair).** `Out.Char`/
   `Out.Int`/`Out.Ln`/`Out.String` at minimum (exactly poc's own
   `Diagnostics.Mod` usage, confirmed by grep — this is the one module
   this phase builds that's simultaneously a poc-own dependency *and*
   one of the Oakwood Guidelines' basic eight) plus the fuller
   Guidelines interface (`Out.Real`, `In.Int`/`In.Real`/`In.Char`/
   `In.String`/`In.Done`) now that formatted values (`REAL` from Phase 9
   step 2, records/pointers from Phase 9 steps 4–6) actually exist to
   print. `Console.Mod` (step 1) is not superseded — it stays the
   minimal, always-available module; `Out.Mod` is additive. Once real
   `Console`/`Out`/`In` modules exist, cross-checking a fixture using
   them against real `voc` (which has its own working `Console.Mod`
   already exercised by `test/conformance/hello` since Phase 0) becomes
   practical again in a way Phase 8 step 13 found it wasn't for any
   FFI-based fixture.
   **Testing**: fixtures covering each `Out`/`In` procedure, matching
   the Phase 8 predeclared-procedure fixtures' own one-fixture-covers-
   the-whole-set style where practical; at least one cross-checked
   against real `voc` per the paragraph above.
   **Implemented (2026-09-20)**: `rtl/llvm/Out.Mod` has voc's `Out`
   (`Open`, `Flush`, `Char`, `String`, `Int`, `Hex`, `Ln`, `Real`,
   `LongReal`, `Ten`, `IsConsole`) and `rtl/llvm/In.Mod` voc's `In` (`Open`,
   `Char`, `Int`, `LongInt`, `HugeInt`, `Real`, `LongReal`, `Line`, `String`,
   `Name`, `Done`). With them and `Modules`, poc's own `Poc.Mod` and
   everything below it now type-check up to the one known obstacle, the
   `WITH` rule in `SemanticActions.Mod` (step 3's note): `poc
   -emit-llvm-ir` of `ModuleInterface.Mod` is clean and the other two stop
   at exactly those 29 errors. Decisions, read from voc's `Out.Mod`/
   `In.Mod`:
   - **`Out` writes through `Console`** and is as unbuffered as it is, so
     output interleaves with `Console`'s and the trap messages in the order
     of the calls and none is lost when a program ends without an `Ln`
     (voc's `Out` buffers 128 characters and flushes at each line end).
     `Flush` and `Open` do nothing.
   - **`Out.Real`/`LongReal` are voc's algorithm step for step**, so they
     print what voc prints - 40 magnitudes at six field widths agree, on
     x86_64 and i686 - and are not always correctly rounded (see the
     Phase 11 table). Two things had to change to carry it over: `ENTIER`
     gives a `LONGINT`, too narrow for the 17 digits, so the whole part is
     cut from the bits of the number (`WholePart`); and the result is
     written in one call, not character by character. `Hex` needs no
     `SYSTEM.LSH`/`ROT`; a negative number gets exactly the `n` low digits
     asked for, as in voc.
   - **`Int` has no wrong answer for the smallest `HUGEINT`**, where voc
     (by its source, not run) prints a fixed wrong string.
   - **`In` reads with `getchar`**, one character ahead except at a line
     end, as voc's does. `Real`/`LongReal` read a line, check it is
     `[+-] digits [. digits] [E|D [+-] digits]`, and hand it to libc's
     `strtof`/`strtod`, so the value is correctly rounded (`0.1`,
     `1.7976931348623157E308`, `4.9E-324` and a float tie all come out
     right, checked by their bits); voc goes through `Strings`, cuts the
     line to 15 characters and never sets `Done`. A line that is not a
     number leaves the variable alone and `Done` FALSE.
   - **`In.Name` reads a word**; voc's stops the program ("Not
     implemented"). **`In.HugeInt`** treats hexadecimal digits without an `H`
     as an error, where voc reads them as a garbage decimal number.
     **`In.Open`** only resets the reader: voc also seeks stdin to the
     start, which cannot be done portably and does nothing for a pipe.
   - **voc's own quirks met**: its `In.HugeInt` takes a `SYSTEM.INT64` -
     a variable of type `HUGEINT` is not accepted (err 123) - so `HugeInt`
     is tested only under poc; and voc folds a constant real expression
     such as `1.0D0 / 3.0D0` into its C with 15 digits (the known lossy-
     constants bug), so the shared `Out` test divides values only known at
     run time.
   **Testing**: `llvm-out` and `llvm-in` (run under poc and voc, output
   equal: strings, integers in decimal and hex, 40 powers of ten and their
   reciprocals and other reals at six widths, infinity and not-a-number;
   `In` fed `input.txt` with numbers, hex, lines, a too-long line, a quoted
   string, reals and single characters to the end of the input);
   `llvm-out-extra` (poc only: the smallest `HUGEINT`, a negative field
   width, output with no final line end, interleaving with `Console`);
   `llvm-in-extra` (poc only: `HugeInt`, hex, `Name`, CR LF, reals read
   exactly or refused). All four run as i686 executables in
   `llvm-i686-runtime`, whose `check` now feeds a fixture's `input.txt` as
   standard input. 188 pass.

6. **`Strings.Mod`, `Math.Mod`, `MathL.Mod`.** The remaining Oakwood
   basic modules poc's own source doesn't itself need but the
   Guidelines still call for shipping — `Strings`' simple substring/
   compare/insert/delete operations, `Math`/`MathL`'s REAL/LONGREAL
   trig and transcendental functions. Pure computation, no OS
   dependency, no new backend mechanism — the most self-contained step
   in this phase.
   **Testing**: one fixture per module exercising each exported
   procedure against a hand-checked expected value.

   **Implemented** (`rtl/llvm/Strings.Mod`, `Math.Mod`, `MathL.Mod`; all
   probed against real voc 2026-09-20; the module header comments have the
   full account). Interfaces are voc's - the Oakwood ones plus `Strings.Match`/
   `StrToReal`/`StrToLongReal` and `Math`'s `log`, `ipower`, `sincos`,
   `arctan2`, `fcmp`, `ErrorHandler`/`err`/`ClearError` - so a program
   compiles under either compiler. What a program can observe:

   - **Neither is a copy of voc's.** voc's `Math`/`MathL` are the OOC
     library's polynomial approximations under the LGPL, and poc is
     BSD-3-Clause, so both are written afresh over libm's double functions
     (`sqrt`, `sin`, `exp`, ..., `ldexp`, `logb`, `nextafter[f]`), the same
     names on Linux and the three BSDs. A `REAL` function widens, calls the
     double function and rounds once. **The build now links `-lm`**
     (`LLVMToolchainDriver.Build`; without it `sin` is undefined at link
     time). The error handling is voc's: a call outside its domain reports a
     code through `Math.ErrorHandler` (default: store it in `Math.err`) and
     returns a fixed value (`ln(x <= 0)`: `IllegalLog`, `-large`; the table
     is in `Math.Mod`'s header); `MathL` reports through the same handler.
   - **Where voc is wrong and poc is not**: `sincos` gives voc's cosine as
     `sqrt(1 - sin^2)`, never negative; `succ` of a negative number moves
     down; `pred(1)` is `1 - ulp(1)`, not the true predecessor; `ulp(1)` is
     inexact in both `Math` and `MathL`; `MathL.power(0, 3)` fails; `MathL.small`
     is 0 and its `MathL.large` a little below the true `MAX(LONGREAL)`; `sin`/`cos` give up
     (`LossOfAccuracy`, result 0) beyond about 9099 in `Math`; a denormal's
     `exponent` is -127. Poc's values are exact or correctly rounded, and
     `fraction`/`exponent`/`scale`/`ulp`/`succ`/`pred` are right for
     denormals and zero (`ulp(0)` is the smallest number). `round` (halves
     away from zero, as voc) clamps to `MIN(LONGINT)`/`MAX(LONGINT)` for a
     number that rounds beyond them.
   - **Differences from voc a program could notice**: `exp` reports
     `Underflow` only when the result is really 0 (voc from about e^-88, in the
     denormal range; `MathL.exp` reports none in voc); `sinh`/`cosh`/`arcsinh`
     have no `HypInvTrigClipped`; `log(x, 1)` is `IllegalLogBase`; `arctanh`
     at or past +-1 gives +-`arctanh(1 - 2^-places)` (voc: another
     approximation of the same idea); `power` and `arctan2` follow `Math`'s
     rules in `MathL` too (voc's `MathL` returns `-large` for a negative
     base). `INT16`/`INT32` are `INTEGER`/`LONGINT` (`SYSTEM.INT16`/`INT32` exist since step 7, as the same aliases).
   - **`Strings`** is Oberon-2 over an array and length, all in `LONGINT`
     so nothing wraps, and never writes beyond `dest` or reads beyond a
     string with no `0X`: a result too long is cut to fit *with* its `0X`
     (voc's `Append`/`Extract` can leave it unterminated or write past the
     end). voc's `Insert` past the end of `dest` and `Replace` at a position
     other than 0 do the wrong thing (swapped arguments in a call; too many
     characters deleted) - poc does what the description says. `StrToReal`/
     `StrToLongReal` accept blanks, a sign, either exponent letter in either
     case, and hand the numeral to `strtof`/`strtod`, so they are correctly
     rounded (voc's digit-by-digit conversion can be an ulp off); no numeral
     gives 0, and a numeral over 511 characters leaves the result alone.
   - **A finding for step 8/Phase 11, not fixed here**: a call of a
     *nested* procedure (one declared inside another) compiles to
     `; unsupported: call target is not a plain procedure` and the build
     still succeeds, running with the call silently missing; found when a
     test helper was nested. poc's own source declares none (checked), so
     self-hosting is not blocked, but a silently missing call is a bad way
     to fail; it should be an error at least (or nested procedures should be
     lowered, which needs a static link).
   **Testing**: `llvm-strings`, `llvm-math`, `llvm-mathl` (run under poc
   and voc, output equal: every procedure, compared with the exact value -
   from Python's `math` - to a relative 1e-5 (`REAL`) or 1e-12 (`LONGREAL`),
   the error codes and the values that come back where voc agrees, a
   handler installed in `Math.ErrorHandler`); `llvm-strings-extra` (poc only:
   truncation with a guard byte after `dest`, an insert past the end, a
   replace not at 0, arrays with no `0X`, a string longer than
   `MAX(INTEGER)`, numerals converted exactly, checked by their bits) and
   `llvm-math-extra` (poc only: the constants and `sqrt(2)` by their bits,
   denormals, `succ`/`pred` around 0 and powers of two, the largest number,
   every error at the edge of the range, `round`'s clamps). All five run as
   i686 executables in `llvm-i686-runtime`. 193 pass.

7. **`SYSTEM` (Appendix C), full list.** *(Phase 9 step 4 already
   pulled forward the pseudo-module itself and `ADDRESS`, `ADR`, `GET`,
   `PUT`, `VAL`, `MOVE`, with their lowering - see there; what is left
   below is `BYTE`, `PTR`, `BIT`, `LSH`, `ROT`, `SYSTEM.NEW`, `GETREG`/
   `PUTREG` and the fixed-width types, starting from that foundation.)*
   Unscheduled until now —
   `AGENTS.md`'s own "Appendix C" section has said so explicitly since
   before this file described any phase past 9. Unlike every other step
   in this phase, `SYSTEM` isn't a real `.mod` source file to write: no
   Oberon-2 implementation gives it one, every exported name is
   compiler magic, the same way `PredeclaredProcedures.Mod`'s ordinary
   ~20 names are — so this step is front-end recognition
   (`SymbolTable.Mod`/`SemanticActions.Mod` treating `SYSTEM` as an
   always-available pseudo-module, the same way `Universe` pre-
   populates the ordinary predeclared names, plus argument-shape
   checking for each procedure) *and* `LLVMCodeGenerator.Mod` lowering,
   together, both from a standing start. The full list below was
   re-checked directly against the report's own Appendix C text
   (`pdftotext` on `Oberon2.pdf`, not assumed from memory or from a
   partial/summarized version of the list) — it's larger than this
   step's own first draft had it, which only carried over `ADR`/`VAL`/
   `BIT`/`GET`/`PUT`/`MOVE`/`LSH`/`ROT` and mistakenly also listed
   `SIZE`/`COPY` as if they were `SYSTEM`'s own; neither actually
   appears in Appendix C at all — both are ordinary §10.3 predeclared
   procedures already, no `SYSTEM.` disambiguation ever needed.

   **Two types**: `SYSTEM.BYTE` (`CHAR`/`SHORTINT` assignable to it; a
   formal `VAR` parameter of type `ARRAY OF BYTE` accepts an actual
   parameter of *any* type) and `SYSTEM.PTR` (any pointer type
   assignable to it; a formal `VAR` parameter of type `PTR` accepts any
   pointer type). Both are genuinely new front-end work beyond a bare
   "recognize `SYSTEM` as a pseudo-module" pass — permissive assignment-
   /parameter-compatibility carve-outs in `Types.Mod`, not just argument-
   shape checks on a procedure call.

   **Six function procedures**: `ADR(v)` (address of a variable — typed
   `SYSTEM.ADDRESS`, not the report's own literal `LONGINT`, per
   `AGENTS.md`'s already-recorded follow-up decision, since `LONGINT`
   can't be assumed address-sized once 32-/64-bit parity, Phase 9, is
   real), `BIT(a, n): BOOLEAN` (bit `n` of `Mem[a]`), `LSH(x, n)`/
   `ROT(x, n)` (logical shift/rotation, result typed like `x`; the
   report's own "integer, CHAR, BYTE" argument category explicitly
   includes `HUGEINT` alongside `SHORTINT`/`INTEGER`/`LONGINT`, per
   `AGENTS.md`'s other already-recorded follow-up decision), `VAL(T, x)`
   (reinterpret `x` as type `T`) — and `CC(n): BOOLEAN`, explicitly
   **not** implemented (see below).

   **Five proper procedures**: `GET(a, v)`/`PUT(a, x)` (raw load/store
   at address `a`), `MOVE(a0, a1, n)` (`M[a1..a1+n-1] := M[a0..a0+n-1]`),
   and `SYSTEM.NEW(v, n)` — a *second*, distinct `NEW` overload from the
   ordinary predeclared one (`v: any pointer; n: integer` — allocate a
   raw `n`-byte block and assign its address to `v`, no type/dope-vector
   involvement at all, unlike the ordinary `NEW(v)`/`NEW(v, x0, ...,
   xn-1)` forms Phase 9 step 5/7 build) — needing its own disambiguation
   in both `PredeclaredProcedures.Mod`'s existing `NEW` checking and
   `LLVMCodeGenerator.Mod`'s existing `NEW` lowering, keyed on whether
   the call resolves through `SYSTEM` or through `Universe`. `GETREG(n,
   v)`/`PUTREG(n, x)` are the other two the report defines — explicitly
   **not** implemented, alongside `CC`, for the same reason (below).

   **Explicit non-goal within this step: `CC`, `GETREG`, `PUTREG`.** All
   three are tied to a specific machine's raw register/condition-code
   model — the report's own Appendix C header says so directly ("The
   following specifications hold for the implementation of Oberon-2 on
   the Ceres computer"), and `GETREG`/`PUTREG`'s own definition
   (`v := Register_n` / `Register_n := x`) presupposes a fixed, numbered
   physical register file to index into. LLVM IR has no such thing to
   expose: it's virtual, SSA-form, and register-allocation-agnostic by
   design, with no "register n" or raw condition-code bit surviving
   past an arbitrary instruction sequence for `CC` to test. voc itself
   only type-checks these three (confirmed by reading `OPB.Mod` in
   voc's own source — argument-shape validation only, e.g. `GETREG`/
   `PUTREG`'s register-number-in-range check), not something this
   project has any evidence it lowers to anything meaningful on a
   non-Ceres target either. Nothing in poc's own source, no Oakwood
   module, and no fixture needs them — revisit only if a real, concrete
   need for one surfaces.

   The remaining nine (two types, four function procedures, three
   proper procedures) lower straightforwardly: `ADR` to `ptrtoint`,
   `VAL` to a bitcast-shaped reinterpretation between same-width types,
   `GET`/`PUT` to a raw `inttoptr`-then-load/store at the given address,
   `MOVE` to a byte-by-byte or `llvm.memmove`-backed copy, `BIT` to a
   loaded byte plus a shift/mask test, `LSH`/`ROT` to LLVM's own shift/
   funnel-shift instructions, `SYSTEM.NEW(v, n)` to the same allocator
   Phase 9 step 4 built, called with a raw byte count instead of a
   type-derived size. Does not touch `SYSTEM.INT8..64`/`SYSTEM.SET32/64`
   — those are voc's own extensions beyond `Oberon2.pdf`/Appendix C, not
   something poc's own language needs to match (this file's own
   bootstrap-terminology section already excludes them from what poc's
   source may use).
   **Testing**: fixtures for each implemented procedure — `ADR`/`GET`/
   `PUT` round-tripping a known value through a raw address, `MOVE`
   copying between two arrays and confirming the byte contents, `BIT`
   testing known-set/known-clear bits, `LSH`/`ROT` against hand-computed
   results for both directions, `VAL` reinterpreting between two same-
   width types, `SYSTEM.NEW(v, n)` allocating a raw block and writing/
   reading through it, `SYSTEM.BYTE`/`SYSTEM.PTR` accepting the
   permissive actual-parameter shapes the front-end carve-out allows —
   all on both the 32-bit/64-bit word-size axis (this step's own
   address-width dependence makes it a second, independent place -
   alongside Phase 9's own cross-cutting discipline - where getting the
   size-dependent axis right from the start matters).

   **Implemented** (`SymbolTable.SystemScope`, `PredeclaredProcedures.Mod`,
   `SemanticActions.Mod`, `Types.Mod`, `LLVMCodeGenerator.Mod`; probed against
   real voc 2026-09-20). Resolving the contradiction above (the step's
   parenthetical lists the fixed-width types, a later paragraph excludes
   them): `INT8`/`INT16`/`INT32`/`INT64` and `SET32` are **implemented**, as
   plain aliases of `SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT`/`SET`; there is no
   `SET64`. Being aliases they have the `-O2` widths (8/16/32/64 bits) and
   are *not* size-model-aware: under `-OC` `SYSTEM.INT32` is a 64-bit `LONGINT`
   and `SYSTEM.INT16` a 32-bit `INTEGER`. That is enough for what the runtime
   needed them for, but the promised migration of the FFI declarations in
   `Platform.Mod`/`Files.Mod`/`Math.Mod` (C `int` written as `LONGINT`) is
   **not done**, since it would only be right under `-O2`; a real fixed-width
   `INT32` (a distinct type, whose width does not follow the model) is a
   Phase 11 row. `CC`, `GETREG` and `PUTREG` are not implemented, as decided.
   What a program can observe:

   - **`SYSTEM.BYTE`** is one byte. `CHAR` and `SHORTINT` values are assignable
     to it, not back (use `VAL`), and it has no `ORD`. A `VAR x: ARRAY OF
     BYTE` parameter takes a variable of any type: the hidden length is the
     actual's size in bytes (for an open-array actual, its element count
     times the element size), so `Copy(x, y)` over two records works like
     voc's. Value `ARRAY OF BYTE` takes only byte arrays (voc too).
   - **`SYSTEM.PTR`** is a pointer to an empty record. Any pointer is assignable
     to it and a `VAR p: PTR` parameter takes any pointer variable;
     `=`/`#` between a `PTR` and any pointer (or `NIL`) is allowed (voc
     rejects the mixed comparison). **Deviation from voc**: a `PTR` cannot be
     dereferenced, type-guarded, tested with `IS`, or be a `WITH` variable
     ("assign it to a typed pointer first"), nor be `NEW`'d as an ordinary
     pointer - voc accepts some of these and the backend cannot lower them
     soundly.
   - **`LSH(x, n)`/`ROT(x, n)`** work at `x`'s own width (`CHAR`/`BYTE`: 8 bits,
     unsigned; `HUGEINT`: 64) and the result has `x`'s type - a `CHAR` shifted
     is a `CHAR` (voc gives a signed integer). A negative `n` shifts or
     rotates the other way. A `LSH` count of the width or more gives 0 and
     `ROT` counts are taken modulo the width; both are defined (voc's are the
     C shifts, undefined there). Lowered branch-free.
   - **`BIT(a, n)`** is voc's, not the report's byte-at-`a`: bit `n` of the
     `SET`-sized word at `a`; `n` outside the word is `FALSE`.
   - **`SYSTEM.NEW(v, n)`** allocates `n` zero-filled bytes (tag 0: the block is
     untraced by the collector, so it must not hold the only reference to
     anything) and assigns the address to any pointer variable `v`. `n <= 0`
     or a size that overflows is the length trap of step 7 of Phase 9 (exit 7,
     "Too many, or negative number of, elements in dynamic array"); a heap
     that cannot supply the block leaves `v` NIL. The call is told from the
     ordinary `NEW` by its designator having a qualifier (`SYSTEM.NEW` - the
     bare `NEW` stays the predeclared one).
   - **Not lowered** (found, not fixed): a guard followed by an index
     (`any(T)[i]`) and a guard to a pointer-to-array type stay `; unsupported`
     in the backend; with `PTR` guards rejected only this reaches user code
     through ordinary pointer types, where it already did.

   **Testing**: `llvm-system-shifts` and `llvm-system-bytes` (shared with voc,
   output equal: every `LSH`/`ROT` direction and width, `BIT`, byte-array
   parameters over scalars, records and open arrays, `BYTE` narrowing),
   `llvm-system-extra` (poc only: counts at or past the width, `CHAR`/`BYTE`
   operands, an out-of-range `BIT`, the `INTn`/`SET32` aliases, `PTR`
   comparisons, `SYSTEM.NEW` blocks including a reclaim loop of 20000 blocks
   of 100000 bytes), `llvm-system-new-trap` (exit status 7),
   `semantic-reject-system-byte-ptr` (19 diagnostics). All three run
   fixtures are in `llvm-i686-runtime` and match the 64-bit output; all
   three also build and run under `-OC`. 198 pass.

8. **Self-hosting bootstrap.** Stage 0 (`voc`) compiles all of poc
   (front end + LLVM backend + every `rtl/llvm` module built in steps
   1–6, `SYSTEM` lowering from step 7, and Phase 9's own GC) → Stage 1
   poc compiles poc's own source again, now genuinely linked against
   `rtl/llvm` rather than voc's own runtime → Stage 2 poc compiles it a
   third time; diff Stage 1 vs. Stage 2 output (modulo embedded
   timestamps/paths) for the classic self-hosting fixed point. This is
   the final step of this phase (and of the LLVM-backend line of work
   generally) precisely because it's the one step needing *both* Phase
   9's full language parity *and* this phase's own runtime library —
   the bootstrap terminology section at the top of this file has
   described Stage 0/1/2 since Phase 0, but Stage 1 was never reachable
   until both were done. `SYSTEM` (step 7) isn't itself a bootstrap
   prerequisite — poc's own source doesn't import it (confirmed by the
   same `IMPORT` grep this phase's own Goal cites) — it's grouped into
   this phase for the reasons given there, not because self-hosting
   needs it. Once Stage 1 passes the full conformance suite, `voc` is
   retired from the day-to-day build loop and kept only as a comparison
   oracle (per the bootstrap terminology's own existing wording) —
   `tools/bootstrap/` gains its Stage 1/Stage 2 scripts here, alongside
   Stage 0's existing ones.
   **Testing**: Stage 1 vs. Stage 2 output diff as the fixed-point
   proof; full conformance suite must pass under Stage 1 before `voc`
   is retired from day-to-day use.

**Testing summary**: compile+link+run+diff fixtures throughout (no
purely-static/golden-IR step this time — every module here is either OS-
facing or produces directly observable output), culminating in step 8's
Stage 1/Stage 2 self-hosting fixed point — the point this file's
"Decisions locked in" table's `voc` framing ("bootstrap compiler...
until poc can compile itself") finally stops applying.

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
| `ModuleInterface.FormatInt` negates its argument, so a `CONST` at a `LONGINT`'s minimum prints as a bare `-` in a `.sym` (`MIN(HUGEINT)`, or `MIN(LONGINT)` under `-OC`) | Open design questions | bug, found not fixed |
| Value-argument predeclared functions in a `CONST` (`ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`, `LONG`, `SHORT`, `ODD`) - `ASH` is done | Open design questions | gap, "real, separate, future work" |
| A computed `REAL`/`LONGREAL` constant of extreme magnitude (`MAX(LONGREAL) / 2`, `1.0D300 * 1.5`) cannot be exported to a `.sym`: `ParseReal` is not correctly rounded, so no text verifies | Phase 9 step 10 | bug, found not fixed |
| `Out.Real`/`Out.LongReal` are voc's algorithm, not correctly rounded (a decimal exponent estimated as 77/256 of the binary one, scaling by a floating-point power of ten exact only to 10^22): the last digits of a number outside about 10^-22..10^22, or the 17th of a LONGREAL, can be off. The same shortcoming as `ParseReal`'s; one correctly rounded converter each way would close both | Phase 10 step 5 | gap, found not fixed |
| `ENTIER` of a real beyond a `LONGINT` gives garbage (poc: `-2147483648`; voc, which wraps: `-727379968` for 10^12 under `-O2`): the report defines `ENTIER` for values that fit, but a `HUGEINT`-valued one - or a trap - would be kinder | Phase 10 step 5 | decision |
| A call of a nested procedure is emitted as `; unsupported: call target is not a plain procedure` and the build succeeds, with the call missing: make it an error, or lower it (static link) | Phase 10 step 6 | bug (silent), decision |
| `SYSTEM.INT8..INT64`/`SET32` are aliases of the `-O2` types, so `SYSTEM.INT32` is 64 bits under `-OC`; a real fixed-width family (and `SET64`), after which the C `int` declarations in `Platform`/`Files`/`Console`/`Math` move to `SYSTEM.INT32` and `-OC` self-hosting can work | Phase 10 step 7 | gap, decision |
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

2. **Known defects and unfinished corners.** Small, concrete, each with a
   fixture that fails first.
   - Fix `FormatInt`: build the digits from the negative side (or peel the
     last digit before negating), the way `LLVMCodeGenerator.AppendLongInt`
     already had to be fixed at the same value; extend
     `module-interface-write` (or a sibling) with `MIN(HUGEINT)` and, under
     `-OC`, `MIN(LONGINT)`.
   - Check whether a `.sym` can carry a number that depends on the target.
     A `CONST` folded from `SIZE(T)` of a pointer, or from a size-model-
     dependent `MAX`/`MIN`, is printed as its folded value, while `AGENTS.md`
     says a `.sym` is target-independent; `-emit-interface` alone resolves no
     `-target`, so it uses the 32-bit default. If that is real, decide
     between printing the expression instead of the value and rejecting
     the combination, and test it at both word sizes.
   - Export extreme computed real constants: tier 2 of `ModuleInterface`'s
     real formatter searches for decimal text that `ConstantEvaluator.
     ParseReal` reads back exactly, and for a value like `1.5D300` written
     as `1.0D300 * 1.5` none does (the bound itself, `MAX(LONGREAL)`, is
     handled by name since Phase 9 step 10). Either make `ParseReal`
     correctly rounded - `references.md` lists Clinger and Steele-White for
     exactly this - or export such a constant as an expression, or refuse
     it with a clear message instead of the current "failed to find a
     round-trip-safe text representation".
   - Fold value-argument predeclared functions in `CONST`s, sharing what
     Phase 9 step 10 built for `ASH`: recursively evaluate the argument,
     apply the function's own value transform. Probe voc for each one - which
     it folds, and what it rejects (`CHR` of a value out of range, `ENTIER`
     of a value that does not fit) - and match it.
   - Close the two "revisit opportunistically" notes by decision, not by
     work: the guard-then-selector workarounds in `Types.Mod`,
     `MemoryLayout.Mod` and `SemanticActions.Mod` stay as written (they
     are correct, tested, and rewriting the Appendix A predicates for style
     is a risk with no payoff); `-show-interface` is dropped unless a
     concrete need shows up in the meantime. Each gets its sentence in
     `AGENTS.md` and its entry closed here.

3. **Run-time semantics.** Each of these is a place the report is silent
   and voc chose something; the step probes voc, writes down what it does
   and what poc does, and decides.
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
   - *Open-array limits.* Decide whether more than 8 open dimensions is
     worth supporting (voc's own limit is the thing to look up) and
     whether skipping the copy of a value open-array parameter that the
     procedure never writes is worth doing; the second is a code-size
     and speed matter, so it needs a use of the parameter analysis the
     compiler does not yet have - drop it unless a measurement says
     otherwise.

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
   - *Assignment of one `ARRAY OF CHAR` to another, and rule 6.* The three
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
   - *`HUGESET`.* Under `-O2` a `SET` is 32 bits and a `LONGINT` 32 bits,
     under `-OC` both 64: `SET` follows `LONGINT`. Whether a set as wide as
     `HUGEINT` on every model is wanted is answered from voc's own answer,
     `SYSTEM.SET32`/`SYSTEM.SET64` (voc's; step 7 made `SET32` an alias of
     `SET` and has no `SET64`), which if sufficient means no new predeclared name.
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

8. **Close-out.** `000-todo.org` is brought up to date entry by entry
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
the step 5 debugger sessions are fixtures too; step 8's whole-suite run
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

- **External procedure declaration syntax**: decided 2026-09-16, grammar/
  symbol-table side implemented in Phase 6 (2026-09-16) — a bracketed
  string-list attribute after `PROCEDURE`, body-less (`PROCEDURE ["C"]
  Name*(...): T;`, optionally `PROCEDURE ["C", "malloc"]
  AllocateBytes*(...): T;` to override the linkage name), per
  `AGENTS.md`'s "External procedures". Needed by Phase 6 for calling C
  functions on Linux/the BSDs, and by Phase 13 for VAX/VMS Calling
  Standard interop. Both backends' actual lowering is still Phase 8/13
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
  future work. (`ASH` was the first, Phase 9 step 10, 2026-09-19; the
  rest are Phase 11 step 2.)
  - `MAX(T)`/`MIN(T)` **implemented** 2026-09-17 for the integer family
    (`SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT`), `SET`, `CHAR` and
    `BOOLEAN` - the same argument set `PredeclaredProcedures.CheckMaxMin`
    already accepts for ordinary type-checking, minus `REAL`/`LONGREAL`
    (see below). `SHORTINT`/`INTEGER`/`LONGINT`/`SET`'s bounds are
    target-word-size-independent but do vary by elementary-type size
    model (`HUGEINT`/`CHAR`/`BOOLEAN` do not - always 8/1/1 bytes); see
    the `-O2`/`-OC` flags entry directly below for how that's resolved.
  - `MAX(REAL)`/`MAX(LONGREAL)`/`MIN(REAL)`/`MIN(LONGREAL)` **not**
    implemented - deliberately scoped out of the above. Unlike the
    integer family, the correct bound is an IEEE 754 largest-finite-value
    fact that should be verified against real voc's own actual behavior
    first (this project's standing "verify against voc before
    implementing" convention), not guessed at, and ties into the
    already-tracked correctly-rounded-float-formatting work (see
    `references.md`). Revisit alongside that, not as part of this pass.
    (Phase 9 step 8 lowered the run-time form; the `CONST` form was
    **implemented 2026-09-19, Phase 9 step 10** - see that step's account,
    including how a `.sym` carries it.)
  - `SIZE(T)` **implemented** 2026-09-17. Unlike `MAX`/`MIN`'s other
    bounds its result is genuinely target-dependent (word size and
    elementary-type size model - `MemoryLayout.Mod`'s own two axes).
    In practice `SIZE(T)` only works for a predeclared or imported `T`
    right now, never a type declared in the *same* module's own `TYPE`
    section - `CheckModuleBody` resolves `CONST` declarations before
    `TYPE` declarations unconditionally, regardless of their relative
    textual order (`000-todo.org`'s "Relax order of declarations" item,
    this file's own "Declaration order" entry below has the full
    voc-verified rationale), a real, concrete instance of that
    already-tracked gap found while testing this.
    Three new conformance tests: `semantic-const-max-min-size`,
    `semantic-reject-const-max-min-too-wide`, `semantic-reject-const-max-
    min-not-a-type`.
  - **`-O2`/`-OC` CLI flags added 2026-09-17** (`Poc.Mod`), addressing
    the "poc has no real `-O2`/`-OC` CLI flag yet" gap the two bullets
    above originally had to work around by assuming `-O2`. Select the
    elementary-type size model (`MemoryLayout.sizeModelO2`/`sizeModelOC`)
    that `MAX(T)`/`MIN(T)`/`SIZE(T)` (and, as a direct consequence,
    ordinary integer-literal typing - `IntegerLiteralType` shares the
    exact same bounds, see `ConstantEvaluator.Mod`'s own header comment)
    fold against; default `-O2`, a later flag wins if given more than
    once, matching `-output-dir`'s own precedent. Implemented as a
    `ConstantEvaluator.SetSizeModel*` exported setter (module `VAR`s,
    recomputed on call) rather than threading a size-model parameter
    through `Evaluate*`'s whole mutually-recursive call graph and every
    one of `SemanticActions.Mod`'s nine call sites - mirrors
    `Diagnostics.fileName*`/`errorCount*`'s own existing "module `VAR`
    set once per compilation, read everywhere" pattern. `SIZE(T)` still
    always uses `MemoryLayout.wordSize32` - there is still no word-size
    (32/64-bit) flag, since nothing before a real backend (Phase 8+)
    makes that axis observable the way `-O2`/`-OC`'s differing
    `SHORTINT`/`INTEGER`/`LONGINT`/`SET` ranges now are. `-dump-layout`
    (Phase 4) is intentionally unaffected - it keeps printing all four
    word-size x size-model combinations regardless of `-O2`/`-OC`, since
    it is a golden-file testing surface for `MemoryLayout.Mod` itself,
    not a preview of one selected target.
    **Found, not fixed, while verifying this**: `ModuleInterface.Mod`'s
    `FormatInt` (used by `-emit-interface` to print a folded integer
    `CONST`'s value) negates its argument (`v := -v`) to build the digit
    string, which overflows - and silently produces just `"-"` with no
    digits - for any value at exactly a `LONGINT`'s two's-complement
    minimum (the same magnitude-has-no-positive-representation asymmetry
    `ConstantEvaluator.Mod`'s own `minHugeInt`/`minShortInt`/etc. already
    had to route around with a computed `-maxX - 1`, never applied here).
    Pre-existing and already reachable via `MIN(HUGEINT)` before this
    session (confirmed: unaffected by `-O2`/`-OC`, since `HUGEINT`'s
    bound doesn't vary by size model) - `-OC` just makes it reachable via
    `MIN(LONGINT)` too, since `LONGINT` is 8 bytes under `-OC`, the same
    width as `HUGEINT`. Only affects `-emit-interface`'s printed `.sym`
    text for this one exact boundary value; `-check`'s type-checking of
    the identical `CONST` is unaffected (confirmed correct via the
    existing `semantic-const-max-min-size` test, which already exercises
    `MIN(HUGEINT)` through `-check`, never `-emit-interface`). Not
    scheduled to any phase yet.

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
  correctness fix, not specific to `MAX`/`MIN`. **Resolved 2026-09-19,
  Phase 9 step 10**: every integer operation a constant expression folds
  re-derives its result's minimal type from the value (voc's `SetIntType`),
  in `CONST` declarations and in ordinary expressions alike; `CONST TooWide
  = MAX(SHORTINT) + 1` is now an INTEGER, and `s := TooWide` is rejected.

- **Declaration order: voc relaxes CONST/TYPE/VAR *section* order, never
  reference order** (`000-todo.org`'s "Relax order of declarations", the
  general form of the `SIZE(Rec)` finding two entries above): tested
  directly against real voc 2026-09-17 with a battery of targeted
  fixtures, not just the one accepting case already known. Two
  independent findings, easy to conflate but not the same thing:
  - voc accepts `CONST`/`TYPE`/`VAR` *sections* in any order, repeated and
    interleaved arbitrarily many times in a single `DeclSeq`
    (`CONST A; TYPE Rec; CONST B = A+1; TYPE Rec2; VAR ...` all compiles) -
    a real extension beyond `Oberon2.pdf`'s grammar, which fixes one
    optional section each, in `CONST`, `TYPE`, `VAR` order. `PROCEDURE`
    declarations, though, must still come after every `CONST`/`TYPE`/`VAR`
    section - voc rejects a `TYPE`/`VAR` section appearing after the first
    `PROCEDURE` (`err 41 END missing`), matching the grammar's own
    `{ProcedureDecl ";" ...}` tail position.
  - Despite that, voc still enforces strict declare-before-use, single-pass
    name resolution throughout - confirmed rejected: a `CONST` forward-
    referencing a later `CONST` in the same section, a `TYPE` forward-
    referencing a later `TYPE` by value (inline field, no pointer), a
    `CONST` referencing a `TYPE` declared in a *later* section, and a
    procedure body referencing a `CONST` or another procedure declared
    later (the latter needs the standard `PROCEDURE^` forward declaration,
    same as poc already requires). The only two forward-reference
    exceptions in the entire language are the two `Oberon2.pdf` already
    documents and poc already implements: a `POINTER`'s own inline base
    type, and `PROCEDURE^`.
  So `SIZE(Rec)` (two entries above) works in voc not because voc allows a
  `CONST` to forward-reference a `TYPE`, but because that fixture happened
  to declare `TYPE Rec` *before* the `CONST` referencing it - a section-
  order relaxation, not a reference-order one. **Decided** (discussion
  2026-09-17): poc should match this precisely - no new forward-reference
  mechanism, just resolve `CONST`/`TYPE`/`VAR` declarations as one linear
  pass over the `DeclSeq` in actual textual order (regardless of which
  keyword introduces each one), instead of `CheckModuleBody`'s current
  three separate whole-section passes (`ResolveConstDecls` then
  `ResolveTypeDecls` then `ResolveVarDecls`). `Parser.Mod`'s `ParseDeclSeq`
  already parses interleaved/repeated `CONST`/`TYPE`/`VAR` sections
  correctly (its outer `LOOP` accepts any of the three keywords, any
  number of times) - the gap is that it then sorts every declaration into
  three separate `SyntaxTree.DeclSeqNode` lists (`constDecls`/`typeDecls`/
  `varDecls`), discarding the cross-section textual order `CheckModuleBody`
  would need to walk them in one pass.

  **Implemented 2026-09-17.** `SemanticActions.Mod`'s old
  `ResolveConstDecls`/`ResolveTypeDecls`/`ResolveVarDecls` (three whole-
  section passes) are replaced by `ResolveDeclSeq`: a `PredeclareTypeNames`
  pre-pass (unchanged in spirit - registers every `TYPE` name across the
  whole `DeclSeq` up front, `obj.pendingTypeNode` set but nothing resolved
  yet, so the `POINTER`-base exception still works regardless of source
  order), then one merged pass dispatching to `ResolveOneConstDecl`/
  `ResolveOneTypeDecl`/`ResolveOneVarDecl` in actual textual order - a
  three-way merge over the three still-separately-typed lists (each
  already in its own order), keyed on each node's own `line`/`column`
  (`SyntaxTree.DeclSeqNodeDesc`'s own header comment has the rationale for
  merging rather than restructuring the AST into one polymorphic list).
  `SyntaxTree.Mod`, `ModuleInterface.Mod`, `Poc.Mod` (`-dump-layout`) are
  untouched - none of them cared about cross-kind order.

  Two real correctness gaps surfaced while implementing this, both fixed
  alongside it, not deferred: the merge makes it newly possible for an
  *earlier* `POINTER`'s own base resolution to eagerly resolve some
  *later* type as a side effect, before that type's own textual turn in
  the pass - `SemanticActions.ResolveQualidentType`'s existing forward-
  reference check was gated behind `obj.pendingTypeNode.line` (cleared to
  `NIL` the moment eager resolution happens) and its first branch
  (`obj.type # NIL`) already short-circuited past the check entirely once
  that happened, so this was actually a **pre-existing** bug, reachable
  even before this change (confirmed with a standalone repro not
  involving `CONST`/`VAR` merging at all: `TYPE P = POINTER TO PDesc; VAR
  r: PDesc; TYPE PDesc = ...;` - poc accepted it, real voc rejects it).
  Fixed by adding `SymbolTable.ObjectDesc.declLine*/declColumn*` (an
  Object's own declaration site, set once by `Insert`, never cleared) and
  checking that instead, before the `obj.type # NIL` fast path rather
  than after; `ConstantEvaluator.LookupBareTypeName` (`MAX`/`MIN`/`SIZE`'s
  own separate lookup, can't import `SemanticActions.Mod`) needed the
  identical fix for the same reason, applied only to unqualified
  (same-module) references - a qualified `M.T` reference's `declLine` is
  a line number in that other, already-fully-checked file's own text, not
  comparable to this module's `expr.line` at all; missing that qualifier
  guard in `SemanticActions.ResolveQualidentType`'s own first attempt at
  this fix broke `semantic-reject-readonly-import-field` (a legitimate
  cross-module `VAR t: trees.Tree` wrongly flagged "forward reference"),
  caught immediately by the conformance suite and fixed by adding the
  guard. Separately, moving `TYPE`'s `CheckExportMark` (the `-` mark
  validity check) into the new up-front pre-declare pass initially
  reported it out of textual order relative to `CONST`/`VAR`'s own
  export-mark errors (caught by `semantic-reject-readonly-mark`'s two
  expected errors coming back swapped); fixed by deferring that call to
  `ResolveOneTypeDecl` instead, so it fires at each type's own turn in the
  merged pass like every other diagnostic, leaving only name registration
  itself in the pre-declare pass. Three new conformance tests:
  `semantic-decl-order-const-refs-later-section-type` (the original
  `SIZE(Rec)` motivating case), `semantic-decl-order-interleaved-sections`
  (`CONST`/`TYPE`/`CONST`/`VAR` in one `DeclSeq`), `semantic-reject-decl-
  order-const-forward-type` (the still-illegal genuine forward case). All
  94 conformance tests pass; the Phase 7 self-check sweep (`000-todo.org`)
  still self-checks the same 8 modules clean as before, unaffected.

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
