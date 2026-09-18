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
   wrong but harmless until Phase 10 gives it a real, different lowering.

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

12. **General multi-module user programs + program entry.** Extend the
    driver to transitively discover and compile every user-authored
    `IMPORT` (via `ModuleInterface.Mod`'s already-resolved import graph),
    not just the fixed rtl set from step 6. Generate a native `main` that
    calls each imported module's init function in import-dependency
    order, then the top (command-line-specified) module's own
    `BEGIN...END` sequence — the same ordering `Oberon2.pdf` §11
    prescribes for module initialization generally.

13. **Fixture promotion + portability verification.** Promote a subset of
    earlier type-check-only fixtures to compile+link+run+diff;
    cross-check output against `voc` compiling the same source where
    practical. Run the same fixtures on Linux and on at least one BSD
    (ideally all three of NetBSD/OpenBSD/FreeBSD) — a distinct `clang`
    target triple per OS from step 2's `-target` flag, so this must be
    verified by actually running there, not assumed from POSIX
    compatibility alone.

**Testing summary**: golden-file `.ll` diffs for steps 1–5 (nothing runs
yet), promoted to compile+link+run+diff from step 6 onward per the
`BACKEND=llvm` harness mode from step 3.

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
  correctness fix, not specific to `MAX`/`MIN`. Not scheduled to any
  phase yet.

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
- **Phase 9 self-hosting**: Stage 1 vs. Stage 2 output diff as the
  fixed-point proof; full conformance suite must pass under Stage 1 before
  voc is retired from the day-to-day build loop.
- **Phase 10**: manual review only (no automated run), explicitly bounded
  in scope as described above.
