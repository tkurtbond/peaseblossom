# Peaseblossom

Peaseblossom is a from-scratch Oberon-2 compiler. The compiler executable is
named **`poc`** (Peaseblossom Oberon Compiler).

## Target backends

Two desired outcomes, i.e. two backends sharing a common front end:

1. An **LLVM-based** backend, for 32-bit and 64-bit machines. Beyond
   Linux, this backend must also run on **NetBSD, OpenBSD, and FreeBSD**
   — a portability goal, not just a word-size one, so the runtime's
   OS-facing layer (I/O, process/argv setup) needs to be written with all
   four Unix-likes in mind rather than assuming Linux-only libc/syscall
   behavior.
2. A **bespoke backend** targeting **VAX/VMS 5.5-2** — a specific, dated
   VMS release on the VAX architecture (pre-dating OpenVMS/Alpha). LLVM
   does not target VAX, so this backend cannot reuse the LLVM path and
   needs its own code generator.

This implies the front end (lexer, parser, AST, semantic analysis/type
checking) should be kept backend-agnostic from the start, with codegen
factored out behind a clean interface, since the two backends have nothing
in common at the instruction-selection level.

## Language specification

Two copies of the Oberon-2 report by H. Mössenböck and N. Wirth are kept
locally under `~/Reference/Computer/Languages/Oberon/`, along with
`pdftotext` extracts (`-layout` preserves columns/tables; `-no-layout` is
plain reading order):

- `Oberon2-Report.pdf` / `Oberon2-Report-{layout,no-layout}.text` — the
  original ETH tech report, dated October 1993 in the body text. Typeset by
  the Oberon system itself; the PDF is a frozen 2015 Ghostscript conversion
  (creation date == mod date, never touched again).
- `Oberon2.pdf` / `Oberon2-{layout,no-layout}.text` — a later revision.
  Authored in WriteNow, first exported to PDF in 2007, **modified again in
  2022**. Content-wise it refines the 1993 text in several places, all in
  one direction (never reversed):
  - Pointers are stated to initialize to NIL by default (§6.4).
  - Forward declaration / redefinition parameter lists must be "identical",
    not just "match" (§10, §10.2) — a stricter, clearer rule.
  - The `Trees` example module's `Init(t: Tree)` (VAR-parameter
    initializer) is replaced by `NewTree(): Tree` (allocating function) —
    an API redesign, updated consistently in both the main example and the
    Appendix D4 browser-output example.
  - The array-compatibility rule (Appendix A) is tightened: `ARRAY OF CHAR`
    parameter matching a string requires the formal to be a **value**
    parameter.
  - `HALT` is simplified from two overloads (`HALT(n)`, `HALT(n, code)`) to
    one (`HALT(x)`).
  - Assorted prose smoothing (e.g. "must be left via a return statement"
    instead of "require the presence of a return statement").

**`Oberon2.pdf` is the authoritative spec for Peaseblossom.** Use
`Oberon2-Report.pdf` only as historical background or when explicitly
comparing the two. Neither file carries a printed revision number, so when
in doubt about a specific rule, treat `Oberon2.pdf`'s wording as
controlling and check the PDF metadata (`pdfinfo`) if provenance matters
again.

## Reference implementation: Vishap Oberon (voc)

Vishap Oberon is used as the reference/bootstrap implementation while
building `poc` — for cross-checking semantics, running comparison test
programs, and (potentially) bootstrapping.

- Installed binary: `/usr/local/sw/versions/voc/git/bin/voc` (and
  `showdef`). Add to `PATH` to use directly.
- Installed libraries/symbol files:
  `/usr/local/sw/versions/voc/git/lib`,
  `/usr/local/sw/versions/voc/git/2/{include,sym}` (O2 size model),
  `/usr/local/sw/versions/voc/git/C/{include,sym}` (OC / Component Pascal
  size model).
- Read-only git clone of voc's source (remote:
  `github.com/vishapoberon/compiler.git`):
  `/usr/local/sw/src/lang/Oberon/vishap/compiler`
  - `src/compiler/OP{B,C,M,P,S,T,V}.Mod` — the compiler passes.
  - `src/library/{misc,ooc,ooc2,oocX11,pow,s3,ulm,v4}` — bundled libraries.
  - `src/runtime`, `src/test`, `src/tools`.
  - `doc/*.md` — Compiling.md, ctags.md, Features.md, Files.md, History.md,
    Installation.md, Porting.md, Winstallation.md.
- Version as of 2026-09-16: "Oberon-2 compiler v2.1.0 [2026/09/16] for gcc
  LP64 on fedora", based on Ofront (J. Templ). Rebuilt since (2026/09/18).
- **The same two paths - the binary and the source clone above - hold on
  every machine poc is developed and tested on** (checked 2026-09-20): atla
  (Linux, the development host), `erekose` (OpenBSD 7.9 i386, "clang ILP32")
  and `terhali` (NetBSD 11 amd64, "gcc LP64"). A program voc builds is linked
  against `<voc>/lib/libvoc-O2.so` (or `-OC`), which only Linux finds by
  itself; BSD needs `LD_LIBRARY_PATH`. A login shell gets it (and voc's `bin`
  on `PATH`) from `~/.bash_profile`, a non-interactive `ssh host cmd` does
  not - so `test/testenv.sh` sets both itself (`VOC_BIN_DIR`, `VOC_LIB_DIR`)
  and the conformance suite does not depend on the caller's profile.

Voc's own extensions beyond the report, documented in `doc/Features.md` —
these are Vishap-specific, not part of the Oberon-2 standard, and should
not be assumed required for Peaseblossom unless deliberately adopted for
compatibility:

- Selectable elementary type sizes via `-O2` (default: 8/16/32/32 bit
  SHORTINT/INTEGER/LONGINT/SET — the classic Oberon-2 sizes) vs. `-OC`
  (Component Pascal sizes: 16/32/64 bit, and a `SET` that stays 32 bits -
  `doc/Features.md`'s table says 64 for `-OC`, but voc's `OPM.Mod` sets
  `SET` to 4 bytes under both, which is what the compiler and its own
  generated C do; poc follows the source, see "`SYSTEM.SET32` and
  `SYSTEM.SET64`" below). `tools/bootstrap/stage0`
  builds poc itself with `-OC` — a codegen-only flag, not a source-syntax
  extension, chosen so poc's own `LONGINT` variables get 8 real bytes of
  storage (needed by `Types.Value.intVal` to hold a full-range `HUGEINT`
  constant without wrapping; see "Language extensions beyond Oberon2.pdf"
  below). This doesn't relax the strict-Oberon2.pdf-syntax constraint on
  poc's own source (see `PLAN.md`, "Bootstrap terminology") — only the
  build flag changed, not what poc's own source is allowed to write.
  Since 2026-09-20 poc's own source also *type-checks* under `-O2` (`poc -O2
  -build src/driver/Poc.Mod` succeeds; the one place that needed a 52-bit
  integer, `LLVMCodeGenerator.DoubleBitsText`, now cuts the fraction into
  two parts that fit 32 bits - fixture `llvm-real-constant-bits`). That is
  only about what the compiler accepts: a poc *built* that way has a 4-byte
  `LONGINT` where it needs 8 (`Types.Value.intVal`, the constant folder,
  `DecimalToDouble`), gets constants wrong and hangs on
  `module-interface-extreme-reals` (35 fixtures fail before it stops), so
  Stage 0/1/2 stay `-OC`.
  `MemoryLayout.Mod` (Phase 4) separately models this same `-O2`/`-OC`
  axis for the *target* language poc itself compiles — orthogonal to this
  voc build flag, which only affects how poc's own source is compiled by
  voc. See `PLAN.md`'s "Open design questions" for that resolution;
  poc has no `-O2`/`-OC` CLI flag of its own yet, since there is no
  codegen for one to govern until Phase 8.
- Extra `HUGEINT` type (64-bit), available even under `-O2`. Peaseblossom
  adopted this one outright as its own extension — see "Language
  extensions beyond Oberon2.pdf" below.
- `SYSTEM.ADDRESS` type, used in place of `LONGINT` for
  `SYSTEM.ADR/BIT/GET/PUT/MOVE`, since `LONGINT` can no longer be assumed
  address-sized on all targets.
- `SYSTEM.INT8/16/32/64` and `SYSTEM.SET32/64` fixed-size types.
- Read-only **value** parameters via a `-` marker (Oakwood guideline 5.13)
  — beyond what either report PDF documents (they only allow `-` on
  record fields / module-level exported identifiers).
- Pointers initialize to NIL by default (`-p`, on by default) — this one
  *does* match `Oberon2.pdf`, corroborating that it's the newer report.
- `-a` (assert halt), `-t` (type guard halt), `-x` (index range halt) on
  by default; `-r` (range check halt) off by default.

`voc` CLI usage: `voc options {files {options}}`. Options before the first
filename set defaults for all files; options after a filename apply only
to that file. Repeating a flag toggles it.

## VAX/VMS documentation: the target is VMS 5.5-2

The VMS target is **VAX/VMS 5.5-2** (August 1992). Take facts about the
system - the linker, MACRO-32, the RTLs, system services, RMS, DCL, the
calling standard - only from manuals for that release or, where its set
does not carry the manual, the nearest earlier 5.x release, checked against
the 5.5 and 5.5-2 release notes. Manuals for later releases
(`OVMS_PROG_ENVIRON.PDF` is VAX 6.0/AXP 1.5, `OpenVMS_RMS_RTL_Library.pdf`
is 7.3, `HP OpenVMS Programming Concepts Volume II` is 2005, and everything
under `VSI/` and the `HPE_*` files) are context for a concept at most.
`~/Reference/Computer/OS/VMS/` holds what we have; a manual found later is
saved there under its original file name. `vax-vms-manuals-to-get.md` lists
which release each local file belongs to, what to fetch and why, and where
(bitsavers); none of it has been downloaded yet.

## Toolchain: LLVM (clang/llc)

Used by `poc`'s Phase 8+ LLVM backend (`PLAN.md`) — `LLVMToolchainDriver.Mod`
shells out to these rather than linking against LLVM's own C++ API.

- Installed via system packages (Fedora), both on `PATH`: `/usr/bin/clang`,
  `/usr/bin/llc`.
- Version confirmed 2026-09-18: `clang version 22.1.8 (Fedora
  22.1.8-4.fc44)`, matching `llc`'s `LLVM version 22.1.8`. Host target
  triple: `x86_64-redhat-linux-gnu`; host default data layout:
  `e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128`
  (from `clang -S -emit-llvm` on an empty `int main(){return 0;}`).
- **Build invocation, decided (`PLAN.md` Phase 8 step 1): single-step
  `clang`.** `clang <file>.ll -o <exe>` accepts textual LLVM IR directly and
  handles assembling+linking itself (confirmed with a hand-written
  `write(2)`-based "hello world" `.ll`, compiled and run successfully). A
  `.ll` file emitted by `LLVMCodeGenerator.Mod` must set its own `target
  datalayout`/`target triple` explicitly (matching the values above for the
  host, or the `-target` flag's chosen triple) — omitting them makes clang
  silently substitute the host triple with a `-Woverride-module` warning,
  which would mask a real target mismatch on cross-compiles. The driver
  also passes `-lm` (Phase 10 step 6): `rtl/llvm`'s `Math`/`MathL` call libm,
  a library apart from libc on Linux and all three BSDs, and `clang` does not
  link it by itself (an undefined `sin` at link time).
  **Stack alignment on 32-bit x86 BSDs** (2026-09-21): the i386 System V ABI
  keeps the stack 16-byte aligned at a call, and the C library there is built
  on it (NetBSD's libm does aligned SSE moves through the frame pointer), but
  LLVM assumes it only for i386 Linux - for NetBSD, OpenBSD and FreeBSD i386 it
  assumes 4 - and a process starts `main` with the stack at 4 modulo 16. So
  for a 32-bit x86 triple whose OS is one of those BSDs (`LLVMTypes.
  NeedsStackRealignment`) poc emits the module flag
  `override-stack-alignment` = 16 (LLVM keeps every call it emits aligned) and
  `"stackrealign"` on `@main` (the one frame that starts misaligned); either
  alone still crashed `sin` on NetBSD. Linux and all 64-bit and ARM targets get
  neither, so their IR is unchanged (`llvm-stack-realign`).
- `llc` is **not** part of the normal build path — reserved as an optional
  `-dump-asm`-style debug aid for reading generated assembly in golden-file
  tests. Usage: `llc <file>.ll -o <file>.s` (its default output filetype is
  already textual assembly; unlike `clang`, it has no `-S` flag — passing
  one is a hard CLI error, `Unknown command line argument '-S'`).

### Known voc bugs affecting poc's own source

Bugs (not spec deviations) found in voc 2.1.0 while writing poc's own
source, worth knowing before puzzling over a bogus-looking error again
during Stage 0/1/2 bootstrapping:

- **Self-recursive call from inside a `WITH` branch, misdiagnosed as
  "incompatible assignment"**: if procedure `P` calls itself from inside
  one of `P`'s own `WITH v: T DO ... END` branches, voc rejects the call
  even when the argument's type is fine — reproduced with a minimal
  `POINTER`/`WITH`/self-call example (not just in poc's own source).
  Calling a *different* procedure from inside the same `WITH` branch is
  unaffected; only literal self-recursion from inside one's own `WITH`
  triggers it. Workaround: save whatever the recursive call needs into a
  local variable inside the `WITH` branch, then make the recursive call
  after the `WITH` statement ends. See
  `src/front/SemanticActions.Mod`'s `ResolveType` for a real instance.

- **`LONGREAL` literal rejected with "Value out of range"**: a `LONGREAL`
  literal whose value is integral and at least 2^31 fails to compile —
  `2147483648.0D0`, `1.0D10`, `4.5D15` all fail; `2147483647.0D0`,
  `1.0D38`, `1.0D300` and any non-integral value compile. Workaround:
  build the number arithmetically (see `LLVMCodeGenerator.DoubleBitsText`'s
  `twoTo52` loop).
- **A `REAL` literal with decimal exponent 38, or a `LONGREAL` one with
  exponent 308, is rejected as "number too large"**, though both are within
  what the type holds: `1.0E38`, `1.5E38`, `3.4E38`, `1.0D308`, `1.7D308`
  fail; `9.9E37`, `1.0D300` compile. There is no way to write a value near
  `MAX(REAL)`/`MAX(LONGREAL)` as a literal - `llvm-ash-max-min` compares
  against `1.0D300`-sized numbers instead (found while writing it).
- **`LONG(SHORT(x))` folded away**: voc simplifies that chain to `x`,
  skipping the narrowing to single precision it exists for. Assign
  through a `REAL` variable instead (see `LLVMCodeGenerator.RealConstant`).
- **Lossy real constants in generated C**: voc prints each `REAL`
  constant with 8 significant digits and each `LONGREAL` one with 15
  (`1.0000000e-001`, `1.00000001490116e-001`), so a constant that needs
  more digits to round-trip reads back as a different value in the C
  compiler. Only matters when cross-checking poc's output against voc's:
  three of `test/conformance/llvm-reals`'s checks fail under voc for
  this reason and pass under poc.
- **`DIV`/`MOD` overflow near `MIN(LONGINT)`**: with a 64-bit `LONGINT`
  (`-OC`), voc's generated `DIV`/`MOD` of a negative dividend within the
  divisor of the minimum give wrong, positive results - `MIN(LONGINT) DIV 2`
  is 4611686018427387903 and `(MIN(LONGINT) + 1) DIV 2` positive too. poc is
  built with voc, so `ConstantEvaluator` never divides such a value
  (`FloorQuotient`/`FloorRemainder`, `ProductOverflows`). voc's own constant
  folder seems to suffer the same way: it rejects the product
  `(-4611686018427387904) * 2` (exactly -2^63, which fits), and its compiler
  dies of SIGFPE folding `MIN(HUGEINT) DIV (-1)`.
- **`CAP` of a character that is not a lower-case letter is masked**: voc's
  `CAP(x)` is C's `x & 0x5F`, so `CAP("7")` is 17X and `CAP("{")` is `[`, in a
  `CONST` and at run time alike. The report defines `CAP` only for letters;
  poc's, folded or generated, changes a lower-case letter and leaves anything
  else as it is (`test/conformance/llvm-const-value-functions`).
- **A row of a multi-dimensional open array passed on as an open array
  ignores the row stride**: with `a: ARRAY OF ARRAY OF INTEGER`,
  `Sum(a[r])` (a call whose parameter is `VAR ARRAY OF INTEGER`) makes voc
  pass `&a[r]` as if `a` were one-dimensional, so it hands over elements
  `r`..`r+n-1` of the flat data instead of row `r` - `Sum(grid[2])` on a
  fixed array is right, `RowSum(grid, 2)` inside a procedure is not. poc
  computes the stride (`test/conformance/llvm-open-array-params` check 8
  is the one check voc gets wrong).

## Language extensions beyond Oberon2.pdf

### HUGEINT (implemented)

An 8-byte signed integer, predeclared alongside `Oberon2.pdf`'s own basic
types (§6.1). Adopted directly from voc's identically-named, identically-
sized extension (see "Vishap Oberon (voc)" above) rather than inventing a
new name — an Oberon-2 programmer reaching for "an integer wider than
LONGINT" already expects this spelling. Implemented in `Types.Mod`
(`HugeInt*`, ranked in the numeric inclusion hierarchy directly below
`REAL` — `LONGREAL ⊇ REAL ⊇ HUGEINT ⊇ LONGINT ⊇ INTEGER ⊇ SHORTINT`, since
every integer type ranks below every real type regardless of width, the
same reason `LONGINT` already ranks below `REAL`), `SymbolTable.Mod`
(predeclared identifier), and `ConstantEvaluator.Mod` (`IsIntegerType`/
arithmetic folding). `VAR`/parameter syntax (Phase 5/6) can declare a
`HUGEINT`-typed value directly now — today it's also reachable as a
`TYPE` alias target (see `test/conformance/semantic-hugeint-type`).
Numeral literal typing (2026-09-17) now picks the minimal type per
`Oberon2.pdf` §5 — `ConstantEvaluator.IntegerLiteralType` (shared by
`EvaluateLiteral`'s `CONST` folding and `SemanticActions.CheckLiteralExpr`'s
general expression typing) selects the narrowest of `SHORTINT`/`INTEGER`/
`LONGINT`/`HUGEINT` a decimal/hex numeral's value fits, using voc's `-O2`
default byte widths (poc has no `-O2`/`-OC` CLI flag of its own yet — see
"`-OC`-equivalent elementary-type-size model" below), and reports "integer
literal too large for HUGEINT" for a numeral past even `HUGEINT`'s own
max instead of silently wrapping. Verified against real voc, including
its own boundary rejections and its "number too large" overflow
diagnostic. See `test/conformance/semantic-integer-literal-minimal-type`,
`semantic-reject-integer-literal-too-wide`,
`semantic-reject-integer-literal-overflow`.

**Appendix A / Appendix C survey for `HUGEINT` (2026-09-16,
`000-todo.org`)**: confirmed by direct inspection, not just design intent
— `Types.Mod`'s Appendix A predicates (`IsInteger*`/`IsNumeric*`/
`Includes*`/`WiderOf*`/`AssignmentCompatible*`) and `SemanticActions.Mod`'s
expression-compatible operator table (`CheckBinaryExpr`) are all rank-based,
dispatching on `BasicTypeDesc.rank` rather than enumerating specific types.
Since `hugeIntRank` was already inserted between `longIntRank` and
`realRank` when `HUGEINT` was first added, every Appendix A rule
(`+ - *`, `/`, `DIV`/`MOD`, `IN`, the six relations, assignment
compatibility, "smallest numeric/integer type including both operands")
already treats `HUGEINT` correctly with zero additional code — the only
textual changes Appendix A's own definitions need are the two already
documented above: "Integer types" gains `HUGEINT`, and the type-inclusion
hierarchy gains `HUGEINT` between `LONGINT` and `REAL`. No further Phase 5/6
work item exists here.
Appendix C (the `SYSTEM` module): a subset was pulled forward into Phase 9
step 4 (2026-09-19) and the rest done in Phase 10 step 7 (2026-09-20) - see
"SYSTEM subset (implemented)" below. Two adjustments beyond the report's
own text follow from decisions made elsewhere in this file: `ADR`/`GET`/
`PUT`/`MOVE`'s address arguments use `SYSTEM.ADDRESS`, not `LONGINT` (see
"`SYSTEM.ADDRESS` type" above - an address-width concern, independent of
`HUGEINT`), and `LSH`/`ROT`'s "`x`: integer, CHAR, BYTE" argument category
includes `HUGEINT` alongside `SHORTINT`/`INTEGER`/`LONGINT`, since it is a
genuine additional integer type by the same Appendix A definition above.

### SYSTEM subset (implemented)

`IMPORT SYSTEM` binds a pseudo-module (no source, no `.sym`;
`SymbolTable.SystemScope`) offering `ADDRESS`, `ADR`, `GET`, `PUT`, `VAL`
and `MOVE`, pulled forward from Phase 10 step 7 because the garbage
collector (`rtl/llvm/GarbageCollectedHeap.Mod`, written as ordinary Oberon-2
over raw addresses) needs them. `SYSTEM.ADDRESS` is deliberately **not**
voc's `LONGINT` alias: it is its own integer type, as wide as a pointer on
the target, and placed among the integers by that width (Phase 11): as wide as
a `LONGINT` or narrower and it is the same as `SYSTEM.INTn` - two types of one
width include each other, a wider includes a narrower and not the reverse.
So a `LONGINT` is assignable to an address where it is no wider (always,
except under `-OC` on a 32-bit target, where it is 8 bytes to the address's
4 and needs `SYSTEM.VAL(SYSTEM.ADDRESS, ...)`), a mixed `ADDRESS`/`LONGINT`
operation is done at the wider width, and on a 64-bit target `ADDRESS` and
`HUGEINT` include each other (`semantic-address-width` has the whole
table). `GET`/`PUT` access memory with no alignment assumption;
`PUT(a, x)` stores `x` at `x`'s own type, so a bare numeral is stored at
its minimal integer type's width (`PUT(a, 5)` writes a `SHORTINT`-sized
value under `-O2`). `VAL(T, x)` between scalars of different widths
sign-extends or truncates - the report leaves it undefined and voc warns.

Phase 10 step 7 added the rest (`PLAN.md` step 7 has the full account; probed
against real voc 2026-09-20). What a program can observe:

- **`SYSTEM.BYTE`** is one byte; `CHAR` and `SHORTINT` are assignable to it,
  not back (use `VAL`). A `VAR x: ARRAY OF BYTE` parameter takes a variable of
  any type, its hidden length the actual's size in bytes.
- **`SYSTEM.PTR`** is a pointer to an empty record: any pointer is assignable
  to it and a `VAR p: PTR` takes any pointer variable; it may be compared
  with any pointer or `NIL` (voc rejects that). **A `PTR` is opaque**: it
  cannot be dereferenced or `NEW`'d (voc rejects both too, errs 57 and 111),
  and **unlike voc it cannot be type-guarded, `IS`-tested or used as a `WITH`
  variable** (voc accepts these for a pointer to a record; for a pointer to an
  array its generated C does not compile) - assign it to a typed pointer
  first. Decided with the user 2026-09-21 (Phase 11, A10): a heap block's tag
  is read through to test its type, which is unsound for a block with tag 0
  (`SYSTEM.NEW`) or an array descriptor. **A guard, `IS` or `WITH` on a
  pointer to an array is a compile error too** (voc's err 85): only records
  extend, so such a test could only name the pointer's own type. It used to
  pass the checker, then either "cannot lower" in the backend or, for `WITH`,
  compile and always exit 6 (`semantic-reject-guard-array-pointer`).
- **`LSH`/`ROT`** work at `x`'s own width and the result has `x`'s type (a
  shifted `CHAR` is a `CHAR`; voc gives a signed integer); a negative count
  goes the other way, and a `LSH` count of the width or more is 0, a `ROT`
  count is taken modulo the width - defined, where voc's are C's undefined
  shifts.
- **`BIT(a, n)`** is a bit string starting at `a`: bit `n` mod 8 of the byte
  at `a + n DIV 8` (floored), bit 0 the low bit of the byte at `a`. Defined
  for every `n` - 32 and up are the following bytes, a negative `n` the bytes
  before `a` - and only the one byte is read, no alignment assumed. Decided
  with the user 2026-09-21 (Phase 11, A11). On a little-endian machine, every
  target poc has, it is voc's result for `n` in 0..63 (voc's `__BIT` reads a
  64-bit word, undefined beyond) and A2's, and it is what the VAX's `BBS`/
  `BBC` do with their signed bit position (VAX Architecture Handbook, 1986,
  ch. 4). Until then poc tested a 32-bit `SET`-sized word and answered `FALSE`
  outside 0..31, which the docs called voc's - true only below 32.
- **`SYSTEM.NEW(v, n)`** allocates `n` zero-filled bytes for any pointer
  variable, untraced by the collector (tag 0: kept while something points at
  it, never scanned inside, exactly voc's `NEWBLK`/`NoPtrSntl`, decided with
  the user 2026-09-21 - it must not hold the only reference to anything);
  `n <= 0` or too large traps
  (exit 7, as `NEW` of an open array), no heap leaves `v` NIL. Told from the
  ordinary `NEW` by the `SYSTEM.` qualifier.
- **`SYSTEM.INT8/16/32/64`** are integers of exactly 1/2/4/8 bytes under both
  size models (Phase 11; they were aliases of the `-O2` types, so under `-OC`
  `SYSTEM.INT32` was 64 bits, which is what kept a C `int` from being spelled
  right - and poc built with `-OC` from running on a 32-bit target). They are
  distinct types, and as in voc, where inclusion goes by size, they take their
  place among `SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT` by byte width
  (`Types.Order`): two of one width include each other (`INT32` and `LONGINT`
  under `-O2`, `INT32` and `INTEGER` under `-OC`; `INT64` and `HUGEINT` under
  both), a wider includes a narrower and not the reverse. An integer constant
  whose *value* fits is assignable to any of them, since a constant's own type
  is its minimal one under the model. `MAX`/`MIN`/`SIZE` work. `LONG` and
  `SHORT` of them, and of `HUGEINT`, go by byte width as in voc (probed under
  both models, Phase 11 step 2): `LONG(x)` is the narrowest of `SHORTINT`/
  `INTEGER`/`LONGINT` strictly wider than `x`, else `HUGEINT`; `SHORT(x)` the
  widest strictly narrower, else `SYSTEM.INT8`. So `LONG` of an `INT32` is a
  `LONGINT` under `-OC` and a `HUGEINT` under `-O2`. `LONG(LONGINT)` and
  `SHORT(SHORTINT)` stay errors, as in the report (voc accepts both). An integer
  *constant* met by an `INT8` in `+ - * DIV MOD` takes the `INT8`'s type when
  its value fits it (Phase 11 step 3), so `b := b + 1` works under `-OC`, where
  a constant is otherwise at least two bytes; `b + 200` or `b + 128` is a
  `SHORTINT` or wider and is not assignable back, as in voc (probed under both
  models, `semantic-system-fixed-width`, `llvm-system-int8-constants`). The
  operation is done at one byte, so an overflow of the *sum* (`l := b + 100`
  with `b = 100`) wraps as it does for every narrow type, where voc's C
  promotes to `int` first - undefined in the report. `CC`, `GETREG` and
  `PUTREG` are not implemented: they
  name a machine's registers and condition codes, which LLVM IR has none of.

### `SYSTEM.SET32` and `SYSTEM.SET64` (implemented, Phase 11 step 6)

`PLAN.md` Phase 11 step 6 has the full account; probed against voc's source and
binary 2026-09-21 (decided with the user). A `SET` has 32 bits under **both**
size models, as in voc (`OPM.Mod`: `-O2` 1/2/4/4 bytes, `-OC` 2/4/8/4) - it
used to follow `LONGINT` and be 64 bits under `-OC`, so `MAX(SET)` was 63 there.
What a program can observe:

- **`SYSTEM.SET32` is `SET`; `SYSTEM.SET64` is a distinct 8-byte set** with
  elements 0..63 (`MAX` 63, `MIN` 0, `SIZE` 8, 64-bit LLVM integer). Neither
  is ordered (`<` is an error) and both take `=`, `#`, `IN`, `+ - * /`, unary
  `-`, `INCL`/`EXCL`, `ORD`, and `SYSTEM.VAL` like any set.
- **A `SET` is included in a `SYSTEM.SET64`, not the reverse**: it is assigned,
  passed by value, returned and compared by widening with zeros; a mixed
  operation is done at 64 bits. `-x` of a `SET` is its 32-bit complement, so
  `a := -{}` for a `SET64` `a` has 32 elements, not 64.
- **A constant set has the narrowest set type its value fits** (voc types a
  constant by the bytes it needs, as it does for integers): `{}`, `{0, 31}` and
  `{40..30}` are `SET`s, `{0, 32}` and `{0..63}` are `SET64`s, and a computed
  one (`{2, 40} * {2, 31}`, `-{2, 31}`) is typed by what it comes out as. A
  constructor with a *variable* element is a `SET`, or a `SET64` if it has a
  constant element above 31: `{n, 40}` is a `SET64`, `{n}` a `SET`, and a
  variable element that is 32 or more is not detected (`{n}` with `n = 40` is
  a shift past the set's 32 bits, undefined - build it with `INCL` on a
  `SET64`). A constant element outside 0..63 is a compile-time error, and
  `INCL`/`EXCL` reject a constant one outside their own variable's range
  (`INCL(s, 63)` for a `SET`). `ORD` of a `SET64` is a `HUGEINT` (voc rejected
  `ORD` of a `SET64` constant when probed).
- **Where poc differs from voc**: voc types a constant *range* `{35..37}` as a
  `SET32` and loses the bits (its `a + {35..37}` on a `SET64` is wrong); poc
  types it by its value. Both are checked in `semantic-set64` and
  `llvm-set64`, which run under `-O2` and `-OC` with the same output.
- **`.sym` files** name the type `SYSTEM.SET64` and write `IMPORT SYSTEM`;
  a constant set is written as its elements, so an importer types it again by
  value (`llvm-set64-import`).

### Pointers, `NEW` and the runtime (implemented, Phase 9 step 5)

Points where `Oberon2.pdf` is silent and poc made a choice (`PLAN.md` step 5
has the full account; all probed against real voc 2026-09-19):

- **NIL handling**: every dereference (`p^`, and the implied one in `p.f`
  and `p[i]`) is NIL-checked and traps ("NIL pointer dereference", exit
  status 4), like voc's default `-p`. So are `NIL IS T`, the type guard
  `NIL(T)` and a NIL `WITH` variable - all three take the same trap, where
  voc says "NIL access" (Halt(-10)); the report is silent on them, and
  poc matches voc's behavior. A failed guard exits 5 and a `WITH` with no
  matching branch and no `ELSE` exits 6. A `NEW` the heap cannot satisfy
  is **not** a trap: the pointer is left NIL, as in voc, and the next
  dereference traps. Only the *behavior* matches voc's; the exit statuses
  are poc's own numbering (voc's Halt codes come out as 246 for NIL, 251
  for a failed guard, 249 for `WITH`).
- **`&` and `OR` always short-circuit** (Appendix A requires it; poc kept
  them eager through Phase 8 while nothing could observe the difference,
  and there is no eager path any more).
- **`NEW` needs the runtime on the import path**: no module imports
  `GarbageCollectedHeap`/`ModuleTable` for it - `poc` adds both to the
  program itself whenever any module calls `NEW`, finding them like any
  imported module (`POC_IMPORT_PATH=<repo>/rtl/llvm` or `-import-path`).
  There is no built-in default directory; a missing runtime is an error
  message naming the module.
- Pointer variables start NIL, locals included (a local holding a pointer
  is zeroed on entry). Heap blocks come back zero-filled.
- Procedure values are Phase 9 step 8's - see "Procedure values, `ASH`,
  `MAX` and `MIN`" below. (`NEW(p, n0, ...)` and pointers to open arrays
  are Phase 9 step 7's.)

### Type-bound procedures and `VAR` record parameters (implemented, Phase 9 step 6)

`PLAN.md` step 6 has the full account; all probed against real voc
2026-09-19. What a program can observe:

- **Dispatch** follows the receiver's *dynamic* type: `v.P(...)` calls the
  procedure bound to what `v` really is, `v.P^(...)` the one bound to the
  base of `v`'s static type. A NIL pointer receiver is a NIL-dereference
  trap (exit 4, "NIL access" in voc), before the procedure starts.
- **`VAR` parameters of record type carry their actual's type** (voc does
  too): a hidden second argument, the actual's type descriptor, follows
  each such parameter - part of the calling convention of every Oberon
  procedure that has one (a call through a procedure value included),
  but not of an external `["C"]` one, which gets the bare address. That is
  what lets `IS`, a guard `v(T)` and `WITH` apply to "a variable parameter
  of record type" (§8.1), which the front end now accepts. Like voc, only
  the parameter's own name qualifies: a plain record variable or a value
  parameter is rejected, and so is a guard of a guard (`x(T)(U)`) or a test
  on a guard (`x(T) IS U`); inside a `WITH` branch the narrowed parameter
  may be guarded and tested again, and `v(T)` may be passed on as a `VAR`
  argument.
- **Two places voc itself falls short**, so poc follows the report: a value
  record parameter accepts an extension of its type (voc's generated C does
  not compile), and a bound procedure of a record written inline under a
  `POINTER TO` can be called (voc gives that record no descriptor and traps
  "NIL access").

### Open arrays (implemented, Phase 9 step 7)

`PLAN.md` step 7 has the full account; all probed against real voc
2026-09-19. An open array - `ARRAY OF T`, or several dimensions
`ARRAY OF ARRAY OF T` - has lengths only known at run time, carried as a
*dope vector* of word-sized integers (as wide as a pointer on the target,
like voc's), outermost dimension first:

- **A formal parameter** (`VAR` or value) is the address of the first
  element, then one hidden length per open dimension - part of every Oberon
  procedure's calling convention, like a `VAR` record parameter's tag, but
  not of an external `["C"]` one, which gets the bare address. A *value*
  parameter is copied into the callee's frame on entry (voc does the same),
  so assigning to it never reaches the caller's array.
- **What may be passed** is what Appendix A calls array compatible: any
  array whose element types are compatible - a fixed array, an open array
  parameter of the caller's own (forwarding), what a pointer to an open
  array points at, a row or element of a larger array - not only the
  identical type, which the checker used to demand of a `VAR` parameter
  (it now matches voc). Fixed element types must still be the *same named
  type*: an anonymous `ARRAY 3 OF INTEGER` inside the formal is not the
  one inside the actual (voc rejects that too). A string literal or named
  `STRING` constant may be passed to a value `ARRAY OF CHAR`; `LEN` of it
  counts the terminating `0X` (`LEN("abc") = 4`), as in voc.
- **Indexing** checks the index against the run-time length (a negative
  index too) and traps like a fixed array's, exit 2; `LEN(a, n)` reads the
  length. `LEN` now has type `LONGINT`, as the checker always said (the
  code generator had typed it `INTEGER`, wrapping a length above 32767).
  `COPY`, string comparison and `NEW` accept open `ARRAY OF CHAR`s too.
- **A pointer to an open array** points at a block that starts with the
  lengths, one word each, then the elements from a fixed offset on (voc's
  own layout, `SYSTEM_NEWARR`); `p[i]`, `p[i, j]` and `p^` work through it
  and a NIL `p` is the usual NIL trap.
- **`NEW(p, n0, ..., nk-1)`** allocates it, one length per open dimension.
  Like voc a length that is not positive - zero included, though the report
  says nothing - traps, exit 7 ("Too many, or negative number of, elements
  in dynamic array", voc's Halt(-20)); so does a size that overflows, which
  voc silently wraps. A heap that cannot supply the block is not a trap:
  the pointer is NIL, as for a record. voc also rejects a *constant*
  length <= 0 at compile time ("illegal value of constant"); poc traps at
  run time instead.
- **Collector**: the block is tagged with the array descriptor of the
  innermost element type, like a fixed array of pointers (see
  `llvm-open-array-new`, which fails without it).
- **At most 8 open dimensions**: an open array type with more (`ARRAY OF
  ... OF T`, nine `ARRAY OF`s) is a compile error where the type is written
  (`Types.maxOpenDimensions`), for a parameter, a pointer base and a named type
  alike; fixed dimensions are not limited. voc's own limit is 127 (its
  `OPB.Mod`; 12 probed), so poc rejects some programs voc accepts. The length
  vector the backend keeps holds eight (Phase 11).
- Not done: the copy of a value parameter is never skipped even when the
  procedure only reads it.
  (A procedure *type* with open-array parameters works: a call through a
  value passes the lengths like any other call - step 8.)

### Procedure values, `ASH`, `MAX` and `MIN` (implemented, Phase 9 step 8)

`PLAN.md` step 8 has the full account; all probed against real voc
2026-09-19. What a program can observe:

- **A procedure name is a value** (`f := Add`, `Apply(Add, 1, 2)`, `RETURN
  Add`, a record field or array element of procedure type) and a value can
  be called (`f(1, 2)`, `t.op(x)`, `tbl[i](x)`, a bare `act` for a proper
  procedure with no parameters). Oberon2.pdf 6.5 forbids a predeclared,
  type-bound or nested (local to another procedure) procedure as a value,
  and poc and voc both reject them; poc also rejects an *external* `["C"]`
  procedure, whose C calling convention differs from the Oberon one a
  procedure value is always called with. A procedure's *name* is not an
  operand of `=`/`#` (`f = Add` is an error, as in voc: compare `f = g`,
  `f = NIL`); a procedure-typed value is.
- **Calling a NIL procedure value** is the NIL trap (exit 4; "NIL access" in
  voc), for a variable, a field (through a NIL pointer too), an element or
  a parameter. A procedure variable that is local (or inside a local record
  or array) starts NIL, like a local pointer - poc's guarantee; in voc it is
  stack garbage.
- **Calling convention**: a value is called with the arguments its
  *type's* parameter list lays out, hidden ones included (a `VAR` record's
  type tag, an open array's lengths) - the same as a direct call of any
  procedure matching the type.
- **`ASH(x, n)`** shifts `x` left by `n`, or right (flooring) for negative
  `n`, and has the wider of `LONGINT` and `x`'s type (so `HUGEINT` keeps
  its 64 bits; voc's own rule). A count of the result type's width or more
  leaves 0 (the sign, for a right shift); voc agrees to 63 and is
  undefined beyond. voc computes in 64 bits, so an `ASH` that overflows
  `LONGINT` and is compared *without* first being stored disagrees with poc.
- **`MAX(T)`/`MIN(T)`** as run-time expressions are the same constants a
  `CONST` folds to, plus `REAL`/`LONGREAL`: IEEE 754's largest finite value
  and its negation (3.4028234663852886D38 and 1.7976931348623157D308). voc's
  `MAX(LONGREAL)` is deliberately a little low, 1.79769296342094D308 (its
  own `OPM.Mod` says so); poc gives the true one. The `CONST` form folds
  to the same values (Phase 9 step 10; see "Constant expressions" below).
- `ASSERT` remains undecided (`PLAN.md`'s open design question).

### Constant expressions (implemented, Phase 9 step 10)

`PLAN.md` step 10 has the full account; all probed against real voc
2026-09-19, under both size models. What a program can observe:

- **A constant integer expression has the minimal type its value fits**, not
  the wider of its operands' types (Oberon2.pdf 5 says so of "an integer
  constant"; voc re-types after every folded operation). `2 * 100 + 2 * 10`
  is the INTEGER 220 (it used to wrap at SHORTINT width), `MAX(SHORTINT) + 1`
  an INTEGER, `-128` a SHORTINT though `128` is an INTEGER, `100000 * 100000`
  a HUGEINT. The same rule applies in a `CONST` declaration and in an
  ordinary expression (`s := 127 + 1` is rejected for a SHORTINT `s`), and
  the bounds follow `-O2`/`-OC`. A real, BOOLEAN or SET constant expression,
  and a relation between constants, is not folded outside a `CONST`; nothing
  observable depends on it.
- **Folding is done in 64 bits and is an error only past HUGEINT**: "constant
  sum/difference/product/negation/quotient too large for HUGEINT" (voc's
  errors 203-207), and "division by zero" for a constant `DIV`/`MOD`. The
  error is reported at compile time in a statement as well as in a `CONST`.
  `DIV`/`MOD` of constants floor. Integer constants compare exactly.
- **`ASH(x, n)` of constants folds**: a count outside -62..62, or a left
  shift whose result does not fit HUGEINT, is an error (voc's error 208,
  same boundaries). The result is at least a LONGINT, wider if `x` or the
  value needs it - voc keeps LONGINT and silently truncates (`l := ASH(1, 40)`
  stores 0 under `-O2`), poc types it HUGEINT, making that assignment a
  compile error - and, like voc, is not shrunk afterwards: `ASH(1, 3)` is a
  LONGINT.
- **`ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`, `LONG`, `SHORT` and `ODD` of
  constants fold** (Phase 11 step 2, probed against voc under both models: the
  table is `test/conformance/semantic-const-value-functions`, which also lists
  the rows where poc differs). `ORD` takes a `CHAR` or a one-character string
  and is an `INTEGER`; `CHR` takes 0..255; `ABS` of an integer has the minimal
  type its value fits and `ENTIER` is a `LONGINT`; `LONG`/`SHORT` follow the
  checker's types and round a real through single precision; `SHORT` of an
  integer constant is always an error (a constant's type is minimal, so its
  value never fits the shorter one). An argument that does not fit is a
  compile-time error, in a statement as well as in a `CONST`. `ENTIER` of a
  value beyond the model's `LONGINT` is an error too, and at run time a trap
  (next bullet).
- **`ENTIER` of a value that does not fit a `LONGINT` is a trap** (Phase 11
  step 3, `doc/phase-11-inventory.md` A4, decided with the user 2026-09-21):
  x >= 2^31 or < -2^31 under `-O2`, 2^63 under `-OC`, an infinity or a NaN
  stops the program with "ENTIER argument out of range for LONGINT" on stderr,
  exit status 8. The result stays a `LONGINT`, as in the report (which defines
  `ENTIER` only for a value that fits) and in every dialect surveyed - voc, the
  A2 and Oberon V4 compilers, obc, Component Pascal - none of which checks it: voc
  wraps under `-O2` (`ENTIER(10^12)` is -727379968) and gives the hardware's word
  (INT64_MIN) under `-OC`; poc used to answer -2147483648, from an LLVM `fptosi`
  whose result for such a value is poison. A `HUGEINT` result was rejected: it
  helps only `-O2`, and breaks `n := ENTIER(x)` for a `LONGINT` `n`. Checked by
  `llvm-entier-trap` under both models.
- **`MAX`/`MIN` of `REAL` and `LONGREAL` are constants**: IEEE 754's
  largest finite values and their negations, as at run time.
- **A `CASE` label must lie in the range of the selector's type** (Phase 11
  step 3): `CASE b OF 128:` for a `SYSTEM.INT8`, or `CASE s OF 200:` for a
  `SHORTINT` under `-O2` (one byte), is an error, voc's err 60 "wrong type of
  case label" - poc's message is "case label is outside the range of the CASE
  selector's type", and it checks both ends of a range where voc looks only at
  the low end (`CASE b OF 1..300:` compiles under voc). It used to be accepted
  and produced IR clang refused (`semantic-case-label-range`).
- **`.sym` files**: a folded integer is written as its value, so an importer
  re-types it minimally (`ASH(1, 3)` is a SHORTINT there); a real constant
  that is exactly `MAX`/`MIN` of `REAL` or `LONGREAL` is written as
  `MAX(LONGREAL)` and so on. Any other computed real exports too, whatever
  its magnitude (`1.0D300 * 1.5`, subnormals): since Phase 11 step 2
  `ConstantEvaluator.ParseReal` is correctly rounded (`DecimalToDouble`, exact
  big-integer arithmetic), and the `.sym` text is the shortest digits, at most
  17, that read back to the very value (`module-interface-extreme-reals`).

### Nested procedures (implemented, Phase 11 step 8)

`PLAN.md` step 8 and `doc/nested-procedures.md` have the full account; the
front end always accepted them, the LLVM backend used to reject them with an
error (before that it dropped the calls silently). What a program can observe:

- **A procedure may be declared inside another, to any depth, and use the
  variables of every procedure around it**: locals, value and `VAR`
  parameters (a `VAR` record parameter keeps its run-time type, an open array
  its lengths), the receiver of a type-bound procedure, and `FOR` control
  variables. Access is
  by reference: what a nested procedure writes is what the enclosing one reads
  next, a pointer variable of the enclosing procedure stays a collector root
  where it is, and each activation of a recursive procedure has its own
  variables, seen by the nested procedure it called. Names are resolved by
  Oberon's scope rules, so a nested procedure's own declaration of the same
  name hides the enclosing one.
- **A nested procedure is called by name only**, from the procedure that
  declares it or from anything declared inside that, itself included, siblings,
  and the enclosing procedure (recursion); forward declarations (`PROCEDURE ^`)
  work among them for mutual recursion. It is never a procedure value (the
  report forbids it and poc rejects it), never type-bound, and never exported:
  a `.sym` never mentions one. A module-level or type-bound procedure may
  contain nested ones and be exported as usual.
- **How it is done**, visible only in the IR, a debugger or `poc -dump-nested
  <file>` (which prints, for each nested procedure, the enclosing variables it
  needs): a nested procedure becomes a function `@Module.Outer.Inner` (`@Module.
  Type.Method.Inner` inside a type-bound procedure) that takes, after its own
  parameters, one hidden `ptr` per enclosing variable it uses - or reaches
  through the nested procedures it calls - in a fixed order (outermost
  declaring procedure first, then declaration order), each followed by the
  variable's type tag if it is a `VAR` record or its lengths if it is an open
  array. A call passes its own bindings' addresses on. There is no static link
  and no closure: an activation never outlives the one that declared it.
- **`WITH` on a pointer variable follows voc's rule**: a pointer that is
  mentioned, read or written, from a procedure other than the one that
  declares it is never narrowed - a nested procedure of the declaring one, or,
  for a module-level pointer, any procedure (so a `WITH` on a global inside a
  procedure is always an error) - nor is a `VAR` parameter or a qualified
  `M.v`; a `VAR` record parameter or receiver is exempt. "Declares" is by
  identity, so a nested procedure's own same-named variable does not count.
  The error is voc's ("guarded pointer variable may be manipulated by non-local
  operations; use an auxiliary pointer variable"). Until 2026-09-21 poc only
  looked for bare `:=` in nested procedures, missing a `VAR` argument (a
  memory-unsafe program was accepted) and accepting a mere read that voc
  rejects (`semantic-with-leaf-rule`).
- **Limits**: an open array type with more than 8 open dimensions is an error
  (the section above), as anywhere else; a procedure that uses very many
  enclosing variables has that many hidden parameters, which is legal and
  untested at scale. Nothing else is specific to nested procedures.
- Checked (`llvm-nested-*`, `nested-analysis-*`) on Linux x86_64 under `-O2`
  and `-OC`, as 32-bit x86 executables (`llvm-i686-runtime`), and on the local
  VMs: OpenBSD i386 (both size models), NetBSD amd64 and FreeBSD arm64.

### External procedures

`Oberon2.pdf` defines no mechanism for calling procedures implemented in
another language, only the low-level `SYSTEM` module (Appendix C) for
memory/register access. Peaseblossom needs one anyway, so poc's language
has a deliberate, documented extension for declaring an **external
procedure** — analogous in spirit to how this file documents voc's own
extensions (see "Vishap Oberon (voc)" above), except this one is
Peaseblossom's own.

- **Simplest case**: calling external C functions on Linux/Unix-like
  targets (including the NetBSD/OpenBSD/FreeBSD portability goal above) —
  the C calling convention is what LLVM (and `llc`/`clang`) already speak
  natively, so the LLVM backend mostly just needs to emit a `declare` for
  the external symbol and call it.
- **VAX/VMS target**: VMS has its own well-defined, documented **VMS
  Calling Standard**. The VAX/VMS backend will need to implement that
  calling convention for any declared external procedure — this is more
  work than the LLVM/C case, but the convention itself is well-specified
  and stable.
- **Decided (2026-09-16), implemented (2026-09-16, Phase 6's grammar/
  `SymbolTable.Mod`/`SemanticActions.Mod` side): a bracketed string-list
  attribute right after the `PROCEDURE` keyword, following Component
  Pascal/BlackBox's own precedent for declaring foreign (e.g. Win32 DLL)
  procedures** — `PROCEDURE ["C"] Name*(...): T;` with **no body** (the
  missing body is what marks the declaration external; a body-less
  `PROCEDURE` with no such attribute stays a syntax error, same as
  today). The first string names the calling convention (`"C"` for
  Phase 8's LLVM/C-interop case, `"VMS"` for Phase 13's VMS Calling
  Standard case — both accepted now, even though nothing consumes
  `"VMS"` until Phase 13; the LLVM backend reports an external `["VMS"]`
  procedure as something it cannot lower rather than calling it as C, Phase
  11). An optional second string overrides the
  external linkage name, since Peaseblossom's own naming convention (see
  "Naming feedback" — descriptive, often-long identifiers) routinely
  won't match a terse external symbol like `malloc` or `printf`:
  `PROCEDURE ["C", "malloc"] AllocateBytes*(size:
  LONGINT): SYSTEM.ADDRESS;`. Without the second string, the external
  symbol is the procedure's own Oberon identifier verbatim
  (`SymbolTable.ObjectDesc.externalName`). This interacts with the VAX
  backend's 31-character name-mangling requirement (Phase 13, below): an
  external procedure's linkage name is emitted **verbatim, never
  mangled** — it has to match the real external symbol, unlike poc's own
  internally-generated names. Both backends' actual lowering is still
  Phase 8/13 work; Phase 6 only records the linkage info
  (`SymbolTable.ObjectDesc.externalConvention`/`externalName`) for a
  later backend to consume.

## Project state

As of 2026-09-16, `PLAN.md` lays out the full phased roadmap (directory
layout, bootstrap terminology, phase-by-phase build order). Phase 0
(scaffolding + conformance-test harness) and Phase 1 (`Lexer.Mod`,
`Diagnostics.Mod`, minimal `Poc.Mod` with `-dump-tokens`) are complete.
Phase 2 (`SyntaxTree.Mod`, `SemanticActions.Mod`, `Parser.Mod`, `Poc.Mod`
`-check-syntax`) is also complete: the parser covers all of Appendix B and
successfully parses its own Phase 1/2 source. Phase 3 (`Types.Mod`,
`SymbolTable.Mod`, `ConstantEvaluator.Mod`, `Poc.Mod` `-check`) is also
complete: CONST and TYPE declarations are resolved against a real scope,
with full constant folding over the basic types (§6.1) and the numeric
inclusion hierarchy; VAR (§7) and PROCEDURE (§10) declarations are left
for Phase 5/6 per `PLAN.md`'s phase-to-section map. `HUGEINT` (see
"Language extensions beyond Oberon2.pdf" above) was added on top of this
afterward, requiring `tools/bootstrap/stage0` to switch to voc's `-OC`
build flag for adequate host-integer storage. Phase 4 (`Types.Mod`'s
array/record/procedure forms, new `MemoryLayout.Mod`, `Poc.Mod`
`-dump-layout`) is also complete: composite types resolve with real
size/alignment/field-offset computation at both a 32-bit and a 64-bit
target word size. Getting record fields to interact correctly with
Phase 3's forward-POINTER-declaration machinery required extending it
beyond what Phase 3 alone had exercised: named POINTER and RECORD
declarations now register their own Type identity before resolving
what's inside them, so the classic self-/mutually-referential linked-
structure idiom (a record field pointing back to its own enclosing
record, or to another record only reachable through a pointer) resolves
correctly instead of falsely tripping the cyclic-declaration guard - see
`src/front/SemanticActions.Mod`'s `ResolveType` header comment. Array and
procedure types don't get this same early registration (self-reference
through either still hits the plain cyclic guard) - a narrower,
deliberately unaddressed limitation. Phase 5 (`SemanticActions.Mod`'s
`CheckExpr`/`CheckStatement` families, `Types.Mod`'s
`AssignmentCompatible*`/`IsInteger*`/`FindField*`/`NilType*`) is also
complete: VAR declarations (§7), general (not-necessarily-constant)
expression/designator type-checking (§8, including `v(T)`/`IS` type
guards - see below), and every statement form except WITH (§9 - WITH is
deferred to Phase 6 alongside type-bound procedure dispatch, which it
shares machinery with) are all checked by `poc -check`. One scope
boundary is deliberately narrower than the full report, documented in
`SemanticActions.Mod`'s own Phase 5 header comment: a call through a
`Types.ProcedureType` value checks each argument expression but does not
yet match the argument list against the formal parameters (Appendix A's
"matching formal parameter lists" is `PLAN.md`'s own Phase 6 line item, and there
is no way yet to declare a real `PROCEDURE` to test the happy path
against). Writing Phase 5's `CheckExtensionApplicable` surfaced a real,
pre-existing gap in `Parser.Mod` itself while it was being smoke-tested
against poc's own source (`test/conformance/parser-self-check`): a type
guard/cast immediately followed by a selector in the *same* expression
(`x(T).field`) couldn't be parsed at all, for exactly the reason above.
Several already-committed Phase 3/4 procedures had unknowingly relied on
this exact pattern (`Types.Mod`'s `IsNumeric`/`Rank`/`Extends*`/
`ArrayCompatible*`, `MemoryLayout.Mod`'s `DescriptorSize`) - undetected
because none of those files are in `parser-self-check`'s own file list.
All were rewritten at the time to bind the guarded value to a local
variable first, never chaining a selector directly onto a guard/cast.
Resolved 2026-09-17 (`Parser.Mod`'s `TryParseGuardSelector`,
`SemanticActions.Mod`'s `CheckDesignator` `GuardSelector` case - see
`PLAN.md`'s "Type guards in designators") - `x(T).field` parses and
type-checks correctly now, but those Phase 3/4 workarounds were left as
they were rather than revisited, since simplifying already-tested
Appendix A predicates for a purely cosmetic win wasn't worth the risk;
`parser-self-check` itself was not widened to cover `Types.Mod`/
`SymbolTable.Mod`/`ConstantEvaluator.Mod`/`MemoryLayout.Mod` either,
since that remains an unrelated test-harness completeness gap. (Decided
2026-09-20, Phase 11: the workarounds stay as written for good. Where they
are: the Appendix A predicates in `Types.Mod` (`IsNumeric`, `Rank`,
`Extends*`, `ArrayCompatible*`, ...), `MemoryLayout.Mod`'s `DescriptorSize` and
a few sites in `SemanticActions.Mod`; each binds the guarded value to a local
variable instead of writing `x(T).field`. Poc's own parser now accepts the
chained form, so new code may use it; nobody needs to go back and rewrite the
old.) See `src/front/README.md` for the module list.

Phase 6 (`SemanticActions.Mod`'s `ResolveProcDecls`/`CheckArguments`/
`CheckWithStatement` families, a new `PredeclaredProcedures.Mod`,
`Types.Mod`'s `EqualTypes*`/`Method*`/`PredeclaredProcedureType*`) is
also complete: procedure declarations and calls with real Appendix A
parameter-list checking (§10, §10.1 - `Types.ArrayCompatible*`/
`ProcedureTypesMatch*`'s first real callers), type-bound procedures
(receivers, override checking, `r.P^` base-dispatch - §10.2), `WITH`
(§9.11, reusing Phase 5's guard-applicability pair outright), the full
§10.3 predeclared-procedure vocabulary (20 names, confirmed against the
report's own table, which has no `ASSERT`), and the grammar/resolution
side of the already-decided external-procedure-declaration syntax (see
"External procedures" above). `poc -check` now type-checks almost any
single-module Oberon-2 program, `PLAN.md`'s own Phase 5 milestone
finally reached in full. Implementing Appendix A's "matching formal
parameter lists" surfaced a genuine, previously-undetected gap: the
report's own "equal types" (used by that definition) is broader than
`Types.SameType*` (it also covers two independently-written open-array
formal types, which are never the *same* type by pointer identity, since
Phase 4 never interns `ArrayType`s) - `Types.EqualTypes*` closes this and
`ParamListsMatch` now uses it. A second gap of the same shape: Appendix
A's "array compatible" rule 3 (`ARRAY OF CHAR` matching a string
constant) requires the formal to be a *value* parameter specifically
(`AGENTS.md`'s own language-spec notes already flagged this), which
`Types.ArrayCompatible*` alone cannot know since it is a pure type-level
predicate with no notion of parameter mode - handled instead where
`CheckArguments` already knows a parameter's mode.
`PredeclaredProcedures.Mod` cannot import `SemanticActions.Mod`
(circular - `SemanticActions.Mod` is the one dispatching into it), so its
`CheckCall*` takes `CheckExpr`/`CheckDesignator` as procedure-typed
parameters instead - the
standard way to break a mutual-dependency cycle between two single-pass-
compiled modules; see that module's own header comment. Two explicit,
narrower scope boundaries, matching how Phase 4/5 recorded their own: a
function procedure's "must contain a return statement" check is shallow
(rejects only a totally empty body, not a full return-reachability
analysis), and `r.P^` base-dispatch is a narrow special case grafted onto
`CheckDesignator`'s `DereferenceSelector` branch (triggered only
immediately after a selector that resolved to a type-bound procedure),
not a generalization of ordinary pointer dereference. `poc -check-syntax`
against the new/changed front-end files themselves (`Types.Mod`,
`SymbolTable.Mod`, the new `PredeclaredProcedures.Mod`,
`SemanticActions.Mod`, `Parser.Mod`) caught one more real instance of the
guard-then-selector `Parser.Mod` limitation above, freshly introduced in
`PredeclaredProcedures.Mod`'s own `NEW` open-array-dimension check - fixed
the same way, by binding the guarded value to a local variable first.
`parser-self-check`'s own file list remains unwidened (still the same
unrelated, pre-existing test-harness gap noted under Phase 5).

Phase 7 (`ModuleInterface.Mod` (new), `SemanticActions.Mod`'s
`CheckModuleBody`/`ResolveImport`/`FindQualified`, a new `poc
-emit-interface` mode) is also complete: qualified names (`Module.Ident`)
now resolve end to end, backed by a textual, on-disk `<ModuleName>.sym`
interface file. Per a decision confirmed with the user while planning this
phase, a `.sym` file is literally valid Peaseblossom module source
(`MODULE Name; ... END Name.`, exported declarations plus - since Phase 9
step 4a - the unexported ones an importer's layout depends on, see "Hidden
members in `.sym` files" below, every
procedure/type-bound procedure written as a permanently body-less
`PROCEDURE^ ...;` forward declaration) rather than a separate
Appendix-D4-style grammar - `SemanticActions.CheckModule` already
tolerated (confirmed: no such check existed) a forward declaration never
being completed within one compilation, which is exactly what makes an
all-forward-declared `.sym` checkable by the same `CheckModuleBody` used
for real programs. `ModuleInterface.Mod` owns only text I/O in both
directions (`Write*`/`ReadSource*`) and deliberately cannot import
`Parser.Mod` (which already imports `SemanticActions.Mod`, which now needs
to call into `ModuleInterface.Mod` - importing `Parser.Mod` too would be a
real cycle); `SemanticActions.CheckModuleBody` instead takes a
`ParseModuleProc` callback, concretely supplied by `Poc.Mod` (the only
module already importing both `Parser.Mod` and `SemanticActions.Mod`
without creating one) - the same procedure-typed-parameter shape
`PredeclaredProcedures.Mod` already established, one layer up (a
module-level import cycle instead of an intra-module one). A new
`SymbolTable.moduleClass`/`ObjectDesc.moduleScope` binds an imported
module's name (or its alias) into the same top-level scope ordinary
declarations go into, exactly mirroring Oberon2.pdf's own grammar
(`ImportList` is part of the module's declaration scope) - a name clash
between an import and a declaration is caught by `Insert`'s existing
duplicate check for free. Genuine cross-module recursion (resolving one
`.sym`'s own imports) is real, but reading is always from an
already-finalized file on disk, never a re-entry into the module currently
being checked - still, two separately-written `.sym` files can end up
mutually referencing each other after enough separate compiles (documented
in `SemanticActions.Mod`'s own `ImportChain` header comment with a concrete
repro), so `CheckModuleBody` threads a small "currently resolving" name
chain and rejects a real cycle explicitly, mirroring
`SymbolTable.ObjectDesc.resolving`'s existing self-reference-guard idiom
one level up.

`FindQualified` (`SemanticActions.Mod`) is the one shared qualified-name
lookup every qualifier-bearing site now routes through, replacing five
separate "qualified names are not yet supported" rejections found while
implementing this phase (`ResolveQualidentType`, `CheckDesignator`,
`LookupBareTypeName`, and both of `CheckWithGuard`'s variable/type
qualifiers) - more sites than anticipated at planning time.
`ConstantEvaluator.Mod` and `PredeclaredProcedures.Mod` each had their own,
separate qualifier rejection too (constant expressions; `MAX(T)`/`MIN(T)`/
`SIZE(T)`'s bare-type-name argument) - both cannot import
`SemanticActions.Mod` (dependency order/circularity, the same reasons
already documented in each module's own header comment), so each got its
own small, deliberately duplicated version of the same lookup rather than
an injected dependency, continuing this codebase's own established
precedent for that tradeoff.

Testing this phase against the report's own `Trees` example (Ch. 11)
surfaced a real, previously-unobservable correctness bug, now fixed: `-`
read-only export (Oberon2.pdf §4: "read-only in importing modules")
was being enforced unconditionally, including within the very module that
declared the field - which made `NewTree`'s own `t.name := ...` illegal,
even though nothing outside the module could previously reference another
module's field at all (so the distinction was moot before this phase).
Fixed two ways: a bare `VAR`'s own read-only mark is now gated on the
designator's own qualifier (`d.qualifier[0] # 0X`- an unqualified
reference can only ever resolve within the current module's own scope
chain by construction, so this is a sufficient and exact signal); a record
field reached via `.` is gated on whether the field's *owning* record was
declared by the current module (`IsLocalType` when written, since replaced
by an exact `rec.moduleName` test - see "Hidden members in `.sym` files"
below) - needed separately because
a field can be reached *indirectly* through a local variable whose own
type was imported (`VAR t: OtherModule.T; t.f := ...`), which a
qualifier-only check on the outer designator would miss entirely. The
existing `semantic-reject-assign-readonly-field` fixture (single-module,
no imports) was testing exactly the behavior this fix removes; renamed to
`semantic-readonly-field-same-module` and inverted to a positive
"semantic OK" case, with `semantic-reject-readonly-import-field` (new,
genuinely cross-module) taking over coverage of the real restriction.

`Types.ParamDesc` gained a `name*` field and `Types.MethodDesc` gained a
`receiverTypeName*` field (both already available at their existing call
sites in `SemanticActions.Mod`) purely so `ModuleInterface.Mod` can print
real parameter names and the receiver's literal declared type spelling
(which may be a `POINTER TO` alias distinct from the record's own name,
the report's own `Tree`/`Node` idiom) instead of placeholders. Building
`SymbolTable.Mod`'s new `moduleScope` field surfaced a real Oberon2.pdf §4
rule-3 subtlety while writing poc's own source: the forward-reference
exception ("`T = POINTER TO T1`, `T1` declared later in the same block")
covers only that exact top-level shape (confirmed against real `voc`) -
an arbitrary field naming an inline, anonymous "`POINTER TO
NotYetDeclaredRecord`" is rejected as an undeclared identifier, even
though `Object`/`Scope` were already mutually recursive by construction.
Fixed by declaring `Scope* = POINTER TO ScopeDesc;` on its own, ahead of
`Object*`/`ObjectDesc*`, so `ObjectDesc` can reference the already-known
name `Scope` directly. Separately, `Files.WriteString` (confirmed against
real `voc`) writes its argument's terminating `0X` into the file, not just
the characters before it - harmless for Oakwood-library callers that
always read text back through `Files.ReadString`/`ReadLine`, but wrong for
a plain-text `.sym` meant to be read back by `Lexer.Mod`, which would see
a stray NUL between every single piece written; `ModuleInterface.Mod`'s
own `WriteStr` (via `Files.Write`, confirmed to accept a bare `CHAR`
directly) works around this.

Several explicit, narrower scope boundaries, matching how every prior
phase recorded its own: the import search path was cwd-only at first
release (`.sym` files looked up as `Files.Old(moduleName + ".sym")`
relative to the working directory only) - since extended, see "IMPORT
search path" below, as is `.sym` output's own cwd-only default - see
"Output directory" below; `ModuleInterface.Mod` could not, at first,
export a `REAL`/`LONGREAL`-valued `CONST` at all (explicit diagnostic,
not lossy text) - also since resolved, see "REAL/LONGREAL CONST export"
below; a written `.sym`'s `IMPORT` line unconditionally re-exports every
import the module itself declared, not just the ones some exported
signature actually references (avoids a separate used/unused pass over
every printed type - and, since Phase 9 step 4a, load-bearing rather than
merely harmless: a hidden member's type may come from a third module);
`IsLocalType` treated a local `TYPE` alias of an imported record
(`TYPE Local = OtherModule.T`) as local too - a real but rare
read-only-enforcement loophole, closed by Phase 9 step 4a's exact
`rec.moduleName` test; and
a qualified `WITH` variable (`WITH M.v: T DO`) - resolved 2026-09-17, not
by narrowing it but by rejecting it outright, matching real voc: see
`PLAN.md`'s "Type guards in designators" entry, gap (2), and
`CheckWithGuard`'s own header comment in `SemanticActions.Mod`. New conformance coverage:
`module-interface-write` (golden-diffs a `.sym` file itself, not just
stdout), `module-cross-import` (a `Trees`-derived library plus a client
that only ever sees its `.sym`), and four negative fixtures
(`semantic-reject-unknown-module`, `semantic-reject-self-import`,
`semantic-reject-not-exported`, `semantic-reject-readonly-import-field`) -
the cross-module export-visibility tests deferred since Phase 3 land here,
as `PLAN.md` anticipated. `poc`'s own front-end source does not yet use
`IMPORT`-based multi-file checking itself (each module is still built as a
single voc compilation unit via `tools/bootstrap/stage0`), so the
Phase-5-style self-check milestone for this phase is `tools/bootstrap/stage0`
itself succeeding end to end with `ModuleInterface.Mod` compiled in
(confirmed) rather than a new `-check`/`-check-syntax` invocation.

**IMPORT search path** (`PLAN.md`'s "Open design questions", closing the
`000-todo.org` item of the same name): `ModuleInterface.Mod` now searches
the current directory first (unchanged, still required for every existing
multi-module fixture), then a process-lifetime list of extra directories
it owns (`searchPathHead`/`Tail`, `AddSearchPathDir*`/`AddSearchPathList*`/
`ClearSearchPath*`/`FirstSearchPathEntry*`). `Poc.Mod` is the only caller:
it seeds the list from the `POC_IMPORT_PATH` environment variable (colon-
separated, read once via `Platform.GetEnv` at startup) and/or repeated
`-import-path <dir>` flags, both of which may precede any existing command
on the same invocation; `-clear-import-path` empties the list regardless
of where its entries came from; `-print-import-path` prints it and exits.
Since the list only lives for one process's `Run`, list-management flags
only matter combined with a later flag in the *same* command line - two
separate `poc` invocations share nothing. `Platform.GetEnv` is a deliberate,
narrow exception to `Poc.Mod`'s own header-comment rule about avoiding
Vishap-specific extensions: that rule is about *language syntax*
(`HUGEINT`, read-only value params, etc.), not which library modules the
driver may import, and `Modules.ArgCount`/`GetArg` already read the host
environment the same way; `ModuleInterface.Mod` itself never reads the
`POC_IMPORT_PATH` environment variable directly (only `Poc.Mod` does),
though it does import `Platform` itself for an unrelated reason - see
"Output directory" below. New conformance coverage:
`module-import-path` (a library in a `lib` subdirectory, only resolvable
via `-import-path lib`), `semantic-reject-import-not-on-path` (the same
library, without the flag, confirming cwd-only lookup still correctly
fails), and `import-path-print` (golden-diffs `-print-import-path`'s
output across env-only, CLI-only, env+CLI, and clear-then-add
combinations in one invocation each).

**Output directory** (closes `000-todo.org`'s "output directory for build
artifacts" item): `-output-dir <dir>` may precede `-emit-interface` (the
only command that writes a file today - a future Phase 8 codegen command
would take the same parameter) to write `<ModuleName>.sym` there instead
of the current directory; unlike `-import-path` it has no environment-
variable seed (not asked for) and no list (a later `-output-dir` simply
overrides an earlier one). Implementing this surfaced a real, sharp voc
behavioral difference: `Files.Old` (used throughout `ReadSource*`/`Open`)
returns `NIL` cleanly on a missing file or directory, confirmed and relied
on since Phase 7, but `Files.New` does **not** - confirmed against real
voc that writing into a nonexistent directory instead runs the runtime's
own uncatchable `Halt(99)`, which would have taken the whole `poc`
process down. `ModuleInterface.Mod`'s `Write*` now validates the
directory first via `Platform.Chdir` (which does return a plain,
non-crashing error code - confirmed `res=2`/`ENOENT` on a bad path),
saving and restoring the real working directory via `Platform.CWD-`
around the write, and only calling `Files.New` (with a bare file name,
now relative to whatever the current directory is) once `Chdir` has
already succeeded; a `Chdir` failure is reported as an ordinary write
failure with no crash. This is `ModuleInterface.Mod`'s own first `Platform`
import (previously only `Poc.Mod` needed it, for `GetEnv`) - documented on
`Write*`'s own header comment as the same kind of narrow, deliberate
exception to the "no Vishap extensions" rule as `Platform.GetEnv` already
was, and still nothing to do with reading environment variables. New
conformance coverage: `output-dir-write` (golden-diffs both the stdout
message and the written file's contents from a `lib` subdirectory built
fresh by `test.sh`, matching how `test/testenv.sh`'s existing artifact
cleanup already treats generated `.sym` files) and `output-dir-missing`
(confirms a nonexistent `-output-dir` fails cleanly rather than crashing
the process).

**REAL/LONGREAL `CONST` export** (closes `000-todo.org`'s "round-trip-
safe float-to-text formatter" item): `ModuleInterface.Mod` can now export
`REAL`/`LONGREAL`-valued `CONST`s, but via two tiers rather than one
general algorithm - see `LiteralRealLexeme`'s and `FormatRealMagnitude`'s
own header comments for the full detail each summarizes here. (1) The
common case, a `CONST` declared as a bare literal (optionally
unary-`+`/`-`'d) - `Pi* = 3.14159265358979;`, `Neg* = -123.456;` - just
echoes the token's own lexeme text verbatim, via the `SyntaxTree.ExprNode`
now threaded down from `PrintConsts` alongside the already-folded
`Types.Value`; re-lexing/re-parsing identical characters through the
identical `ConstantEvaluator.ParseReal` is trivially exact, no
value-to-text algorithm needed at all. (2) Anything else (a computed
expression like `1.0/3.0`, a reference to another constant) still needs
one, via `FormatReal`/`FormatRealMagnitude` - search increasing precision
(and a small window of neighboring digit values at each one, not just the
nearest rounding) until a candidate verifies exactly against
`ConstantEvaluator.ParseReal` itself, never assumed correct from a
"N significant digits always round-trips" argument. That verification
step surfaced two real, previously-invisible bugs in `ParseReal`, both
now fixed (present since Phase 3, invisible until something finally
printed a folded value at full precision): every numeral literal *inside
ParseReal's own source* (`0.1`, `10.0`, `0.0`) was untyped `REAL`, not
`LONGREAL`, per `Oberon2.pdf`'s own real-literal typing rule, so voc
evaluated each at single-precision before ever widening it - confirmed
with a standalone repro (`"1.5"` parsed back as `1.5000000074505800`, an
exact float32-epsilon error) and fixed by `D0`-suffixing every one of
those literals; and, separately, `ParseReal`'s fixed-point path (plain
digit accumulation) and its scientific-notation path (the same, plus a
repeated-`*10.0D0` exponent-scaling loop) can land on different `LONGREAL`
bit patterns for "the same" number, since floating-point arithmetic isn't
associative - the reason tier (1) exists at all, rather than routing
every `CONST` through tier (2)'s reformat-and-verify approach. New
conformance coverage: `module-interface-real-write` (golden-diffs a `.sym`
with a representative literal/negative-literal/computed-expression mix,
including an unexported one that must not appear) and
`module-interface-real-roundtrip` (the strongest test available without a
backend to actually run anything: `-emit-interface` twice in a row, the
second time treating the first run's own `.sym` as input source, must
produce byte-identical output - direct evidence that
`ParseReal(FormatReal(v)) = v` holds for real, not just that `FormatReal`
believed it did).

**Hidden members in `.sym` files** (Phase 9 step 4a, 2026-09-19 - `PLAN.md`
has the full design and the voc comparison): a `.sym` now carries every
field and type-bound procedure of every record it prints, exported or not
(unexported ones carry no export mark), plus every unexported `TYPE` those
members or any exported signature reach, transitively, printed as ordinary
unexported declarations - so a module extending an imported record can
reproduce its base's layout and `ProcTab` slot numbering itself, at its own
word size and size model. (voc instead stores computed sizes, offsets and
method numbers in a binary `.sym`, which is why it ships one symbol tree
per size model; poc keeps one valid-source `.sym` that carries no layout.
A folded constant in it - `SIZE(T)` of a pointer, a size-model `MAX`/`MIN` -
is a number for the target and size model of the run that wrote it, so
`-emit-interface` output differs by word size and size model there; the
whole-program commands regenerate every import's `.sym` for the actual target,
so a client never reads a foreign one - see `module-interface-target-constants`.)
`ModuleInterface.Write*` finds the needed unexported types by running its
whole printing pass repeatedly with output suppressed until nothing new is
found, then once for real, so marking and printing share every lookup rule.
The invariant "`moduleScope` holds only exported members" no longer holds,
so the reading side enforces export explicitly: `FindQualified` rejects an
unexported name ("identifier is not exported by its module"), and field /
type-bound-procedure selection rejects an unexported member unless the
record that *declared* it (`Types.FieldOwner`/`MethodOwner`, not the record
the access went through) belongs to the current module (`IsLocalRecord`:
every `RecordType` is stamped with its declaring module at creation). An
unexported CONST/VAR/PROCEDURE is still simply absent from a `.sym`, so
naming one still says "undeclared identifier". Verified against real voc
(2026-09-19): hidden base members take no part in an importer's *name*
rules - an extension may declare a field of the same name as a hidden base
field (two distinct fields) and a type-bound procedure of the same name as
a hidden base one with any signature (a new procedure in its own slot, not
an override) - so `Types.FindOverridable` (exported, or declared in the
same module) decides what an extension can override, shared by the checker
and `LLVMTypes`' slot numbering. Whole-program commands (`-emit-llvm-ir`,
`-build`) now regenerate every transitive import's `.sym` from real source
(post-order, into the output directory, which `ReadSource*` searches first)
before checking the top module, since a stale `.sym` would otherwise give an
importer a different record layout than the imported module's own code.
Three previously latent bugs surfaced and were fixed along the way: two
exported names sharing one type printed as the cyclic `A* = B; B* = A;`;
`ResolveProcDecls` treated an override of an *imported* procedure as
completing that procedure's forward declaration (mutating the base's
method and never recording the override); and a function returning a
pointer emitted the invalid placeholder `ret ptr 0`. `poc -show-interface <file>` (2026-09-20) prints the exported-only
view, as voc's `showdef` does, since a `.sym` no longer is one: only the
exported fields and type-bound procedures of each record, plain `PROCEDURE`
headings, unexported types named but not declared; like `-emit-interface`
it reads its imports' `.sym` files and writes nothing.
