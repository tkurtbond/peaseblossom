# Phase 8 — LLVM backend, first vertical slice

Moved here from `PLAN.md` unchanged on 2026-09-25, once the phase was done.
`PLAN.md` keeps the heading, the goal, and a list of the steps, so a reference
elsewhere to "`PLAN.md` Phase 8 step N" means step N here.

**Goal**: a hand-verifiable path from a single user module (plus a small,
fixed runtime module set) to a running native executable that prints
text — the first point `poc` produces an executable at all, on Linux and
at least one BSD.

**Explicit non-goals**, unchanged from the phase-to-report-section map but
worth restating precisely since they bound every design choice below:
`POINTER`/`NEW`/GC, type-bound-procedure dispatch, open-array dope
vectors, full `Out.Mod`/`In.Mod`. **Correction to `PLAN.md`'s earlier
wording**: Appendix D5's tag/ProcTab/BaseTypes layout was previously
listed under Phase 8's `LLVMTypes.Mod`; it has no reason to exist before
dispatch does and is moved to Phase 9 (`doc/history/phases/phase-09.md`). In scope: fixed-size
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
   pinned down by `PLAN.md`'s original wording, resolved during
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
