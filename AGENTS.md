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
  - The `Trees` example module's `Init*(t: Tree)` (initializes a tree the
    caller already allocated; 1993's Appendix D4 browser output
    inconsistently shows it as `Init(VAR t: Tree)`) is replaced by
    `NewTree*(): Tree` (allocating function) — an API redesign, updated
    consistently in both the main example and the D4 browser-output example.
  - The array-compatibility rule (Appendix A) is tightened: `ARRAY OF CHAR`
    parameter matching a string requires the formal to be a **value**
    parameter.
  - `ASSERT` is removed: the 1993 §10.3 table has `ASSERT(x)`,
    `ASSERT(x, n)` and `HALT(n)` (though `ASSERT` is missing from its §4
    list of predeclared identifiers); `Oberon2.pdf` has only `HALT(x)`.
  - The FOR statement (§9.8) is redefined: the equivalence evaluates the
    start value first (`v := low; temp := high`, where 1993 has
    `temp := end; v := beg`), and 1993's "temp has the same type as v"
    becomes: low assignment compatible with v, high expression compatible
    with v, step a nonzero constant "of an integer type".
  - Assorted prose smoothing (e.g. "must be left via a return statement"
    instead of "require the presence of a return statement").

A third text, Appendix A of Mössenböck's *Object-Oriented Programming in
Oberon-2*, 2nd ed. (`oop_in_oberon-2_book.pdf`, book pp. 221-254 = PDF pp.
231-264; OCR'd, so its `oop_in_oberon-2_book-{layout,nolayout}.text`
extracts have character errors), is an intermediate state between the two.
It already has the value-parameter array rule, `HALT(x)`, "must be left
via" and "for a fixed number of times"; it still has 1993's FOR
equivalence, "match" for parameter lists, `Init`, and no NIL-initialization
sentence; and it alone lists `ASSERT` among the predeclared identifiers.
It is background only, like `Oberon2-Report.pdf`.

**`Oberon2.pdf` is the authoritative spec for Peaseblossom.** Use
`Oberon2-Report.pdf` only as historical background or when explicitly
comparing the two. Neither file carries a printed revision number, so when
in doubt about a specific rule, treat `Oberon2.pdf`'s wording as
controlling and check the PDF metadata (`pdfinfo`) if provenance matters
again.

## Reference implementation: Vishap Oberon (voc)

Vishap Oberon is the reference implementation for cross-checking semantics
and running comparison programs, and it is the Stage 0 compiler that
bootstraps poc.

- Binary: `/usr/local/sw/versions/voc/git/bin/voc` (and `showdef`).
  Libraries: `/usr/local/sw/versions/voc/git/lib`. Headers and symbol files:
  `.../2/{include,sym}` (`-O2` size model) and `.../C/{include,sym}` (`-OC`).
- Read-only source clone (`github.com/vishapoberon/compiler.git`):
  `/usr/local/sw/src/lang/Oberon/vishap/compiler`. The compiler passes are
  `src/compiler/OP{B,C,M,P,S,T,V}.Mod`. The bundled libraries are under
  `src/library/{misc,ooc,ooc2,oocX11,pow,s3,ulm,v4}`. Documentation is in
  `doc/*.md` (`Features.md` lists voc's extensions).
- Version: "Oberon-2 compiler v2.1.0 [2026/09/16] for gcc LP64 on fedora",
  based on Ofront (J. Templ), rebuilt 2026/09/18.
- **Both paths are the same on every development and test machine**: atla
  (Linux, the development host), the local VMs `cymoril` (OpenBSD i386),
  `artos` (NetBSD amd64) and `rackhir` (FreeBSD arm64), and the office
  machines `erekose` (OpenBSD i386) and `terhali` (NetBSD amd64). Programs
  voc builds link against `<voc>/lib/libvoc-O2.so` (or `-OC`), which only
  Linux finds unaided. A non-interactive `ssh host cmd` gets neither
  `LD_LIBRARY_PATH` nor voc on `PATH`, so `test/testenv.sh` sets both itself
  (`VOC_BIN_DIR`, `VOC_LIB_DIR`).
- CLI: `voc options {files {options}}`. Options before the first file apply
  to all files, options after a file apply only to that file, and repeating
  a flag toggles it.

**Size models.** Under `-O2` (the default) `SHORTINT`/`INTEGER`/`LONGINT`
are 8/16/32 bits. Under `-OC` (Component Pascal sizes) they are 16/32/64.
`SET` is 32 bits under both: `Features.md` says 64 for `-OC`, but `OPM.Mod`
says 4 bytes, and poc follows the source. poc models the same two for the
programs it compiles (`-O2`/`-OC` flags, default `-O2`; `MemoryLayout.Mod`).

**How poc itself is built.** `tools/bootstrap/stage0` builds poc with voc
`-OC`, and Stage 1/2 also stay at `-OC`, because poc needs an 8-byte
`LONGINT` (`Types.Value.intVal` holds a full-range `HUGEINT` constant; the
constant folder and `DecimalToDouble` depend on it too). This is only a build
flag. poc's own source stays strict `Oberon2.pdf` (`PLAN.md`, "Bootstrap
terminology"), which `make check-strict` (part of `make check`) enforces with
`poc -strict`, and it must also **type-check under `-O2`**: no literal or
constant needs more than 32 bits (`poc -O2 -build src/driver/Poc.Mod`
succeeds; `doc/project-history.md`, "poc's own source under `-O2`").

**voc's extensions beyond the report** (mostly in `Features.md`). Assume none of them
for poc unless it adopted them:

- `HUGEINT`, `SYSTEM.ADDRESS`, `SYSTEM.INT8/16/32/64`, `SYSTEM.SET32/64`:
  adopted, with poc's own rules (see "Language extensions beyond
  Oberon2.pdf" below).
- Read-only parameters marked `-` (`PROCEDURE P(x-: T)`: passed by
  reference, not assignable; Oakwood 5.13, which recommends against it; not
  in `Features.md`, only in voc's `OPP.Mod`): not adopted, and a syntax
  error in poc (see "Read-only parameters" below).
- Pointers start NIL (`-p`, on by default), as `Oberon2.pdf` says too.
- Run-time checks: `-a` (assert), `-t` (type guard) and `-x` (index) are on
  by default, `-r` (range) is off.

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
- **Optimization level** (Phase 11 D13, 2026-09-26): `poc -opt <level>`
  makes `-build` pass clang `-O<level>`, one of `0`, `1`, `2`, `3`, `s`, `z`,
  `g` (not `-O<level>` itself: poc's `-O2`/`-OC` are voc's size-model flags).
  The default is `-O2`, but `-O0` for 32-bit x86, whose reals are x87
  arithmetic (`doc/language-extensions.md`, "Overflow, division and reals";
  poc must run on a Pentium II, so no SSE2). `SYSTEM.GET`/`PUT`/`MOVE` are
  volatile, so an optimized build keeps them. `make check-opt2` builds
  everything at `-O2`, Stage 1/2 included (in `build/opt2`).
- `llc` is **not** part of the normal build path — reserved as an optional
  `-dump-asm`-style debug aid for reading generated assembly in golden-file
  tests. Usage: `llc <file>.ll -o <file>.s` (its default output filetype is
  already textual assembly; unlike `clang`, it has no `-S` flag — passing
  one is a hard CLI error, `Unknown command line argument '-S'`).

### Known voc bugs affecting poc's own source

Bugs in voc 2.1.0 (not deviations from the spec) that affect poc's own
source. Check here before puzzling over an error that looks bogus.
`doc/voc-bugs/README.md` has each one in full, with its workaround:

- A procedure calling itself from inside its own `WITH` branch gets a false
  "incompatible assignment" error (`doc/voc-bugs/with-self-recursion/`).
- An integral `LONGREAL` literal >= 2^31 (`1.0D10`) gets "Value out of range".
- A `REAL` literal with exponent 38, or a `LONGREAL` one with 308, gets
  "number too large".
- `LONG(SHORT(x))` is folded to `x`.
- Real constants in the generated C lose digits (8 for `REAL`, 15 for
  `LONGREAL`).
- `DIV`/`MOD` go wrong near `MIN(LONGINT)` under `-OC`.
- `CAP` of a character that is not a letter is masked (`CAP("7")` is 17X).
- A row of a multi-dimensional open array passed on as an open array
  ignores the row stride.
- A nested procedure gets garbage inner lengths for an enclosing
  procedure's multi-dimensional open-array parameter.

## Language extensions beyond Oberon2.pdf

`doc/language-extensions.md` holds the full text of every section below:
what a program compiled by poc can observe where poc goes beyond
`Oberon2.pdf`, or picks an answer where the report says nothing. Each
section there has the same heading as here, so a reference elsewhere to
`AGENTS.md`, "<section>" leads to the right place. Read the matching section
before you change what the checker accepts or how the backend behaves in
that area.

### HUGEINT (implemented)

An 8-byte signed integer, taken from voc. In the numeric hierarchy it sits
between `LONGINT` and `REAL`. Appendix A's rules go by rank, so they needed
no other change.

### SYSTEM subset (implemented)

`ADDRESS` is its own integer type, as wide as a pointer, not an alias of
`LONGINT`. Also: `ADR`, `GET`, `PUT`, `VAL`, `MOVE`, `BYTE`, `PTR` (opaque:
no guard, `IS` or `WITH`), `LSH`/`ROT`, `BIT` (a bit string starting at `a`),
`SYSTEM.NEW` (untraced) and `INT8/16/32/64` (exact widths under both size
models). `CC`, `GETREG` and `PUTREG` are not implemented.

### `SYSTEM.SET32` and `SYSTEM.SET64` (implemented, Phase 11 step 6)

`SET` has 32 bits under both size models. `SET64` is a separate 8-byte set
that includes `SET`. A constant set gets the narrowest set type its value
fits.

### Pointers, `NEW` and the runtime (implemented, Phase 9 step 5)

Every dereference is checked for NIL (exit 4). A `NEW` that fails leaves the
pointer NIL, unless poc is given `-trap-heap-exhausted`, which makes it trap
(exit 11). `&` and `OR` short-circuit. `NEW` pulls in
`GarbageCollectedHeap`/`ModuleTable` from the import path. Every variable
starts at zero, locals included (Phase 11 D16, 2026-09-26).

### Type-bound procedures and `VAR` record parameters (implemented, Phase 9 step 6)

A call dispatches on the receiver's dynamic type. A `VAR` record parameter
carries its actual argument's type tag as a hidden argument (except in
`["C"]` procedures).

### Open arrays (implemented, Phase 9 step 7)

An open array's lengths travel as a dope vector of word-sized integers. A
value parameter is copied on entry. A pointer to an open array uses voc's
block layout. A `NEW` length that is not positive traps (exit 7). Any number
of open dimensions (at most 8 until 2026-09-25, Phase 11 A17).

### Procedure values, `ASH`, `MAX` and `MIN` (implemented, Phase 9 step 8)

A procedure name can be used as a value, except a predeclared, type-bound,
nested or external one. Calling a NIL procedure value traps (exit 4). `ASH`
has the wider of `LONGINT` and `x`'s type.

### Constant expressions (implemented, Phase 9 step 10)

A constant integer expression has the minimal type its value fits. Folding
is done in 64 bits and is an error only past `HUGEINT`. `ORD`, `ABS`, `CHR`,
`CAP`, `ENTIER`, `LONG`, `SHORT` and `ODD` fold. `ENTIER` out of `LONGINT`'s
range traps (exit 8).

### Overflow, division and reals (decided, Phase 11 C5)

Integer overflow wraps, and that is a promise. `DIV`/`MOD` floor. A zero
divisor raises `SIGFPE` on x86, and on ARM gives a value with no fault. Real
arithmetic is silent IEEE 754 (on 32-bit x86 only at `-opt 0`, its default:
x87). `ENTIER` is the one deliberate trap.

### Array assignment (decided and implemented, Phase 11 A21)

voc's rule is adopted: a fixed array can be assigned from a fixed array no
longer than it, or from an open array, with the same element type. An open
array is never an assignment target. An open source that is too long traps
(exit 9).

### FOR final value (decided and implemented, Phase 11 D10, 2026-09-25)

Stricter than `Oberon2.pdf` §9.8, as voc: `high` in `FOR v := low TO high`
must be assignment compatible with `v`, not merely comparable, so a wider or
real bound is a compile-time error. `low` is evaluated before `high`, as the
report says.

### Declarations after procedures (decided and implemented, Phase 11 A22, 2026-09-25)

`CONST`/`TYPE`/`VAR` sections may follow procedures, not only precede them.
Declare-before-use is unchanged; a late declaration may not hide a name
visible from an enclosing scope; a `POINTER TO` base must come before the
next procedure. `-strict` rejects it.

### Variable initializers (decided and implemented, Phase 11 A23, 2026-09-26)

`VAR a, b: T := e;` - an assignment of `e` to each variable, evaluated once
per variable, before the body (locals on every entry), in declaration order.
Any expression; it sees only names declared before its `:=`. Variables only,
not record fields. `-strict` rejects it.

### What traps, and what does not (Phase 11 C9)

The tables of trap statuses 2-11, what ends a program silently, what nothing
stops, and what is a compile-time error. `poc -trap-location` (C7) prefixes
every trap message with `file:line:column:` and ends it with the procedure,
"(in List.Insert)".

### ASSERT (decided and implemented, 2026-09-25)

`ASSERT(x)` and `ASSERT(x, n)`, `n` an integer constant in 0..255, as in voc.
A failure prints "assertion failed (n)" and exits 10. A constant FALSE
condition is a compile-time error, so a constant one is a static check.
Always on.

### Nested procedures (implemented, Phase 11 step 8)

A nested procedure can use any enclosing procedure's variables, by
reference, through hidden pointer parameters (no static link). It can only
be called by name. `WITH` follows voc's rule for non-local pointers.

### External procedures

`PROCEDURE ["C"] Name*(...): T;` with no body declares an external
procedure. An optional second string gives the linkage name, emitted
verbatim and never mangled: `PROCEDURE ["C", "malloc"] AllocateBytes*(size:
SYSTEM.ADDRESS): SYSTEM.ADDRESS;`. `"VMS"` is accepted but not yet lowered.

### `-strict` (decided and implemented, Phase 11 B2, 2026-09-25)

`poc -strict` makes each extension above an error in the command-line module's
own source (not in its imports). `make check-strict`, run by `make check`,
applies it to all of `src/`. Found with it and fixed for everyone: a guard,
`IS` or `WITH` on a pointer must name a pointer type, and `=`/`#` compare only
related pointers and procedure values of one type.

### Read-only parameters (considered, not adopted)

voc's `x-` formal parameter (by reference, read-only; Oakwood 5.13 recommends
against it) is not in poc. A mark on a formal parameter is a syntax error.

### Underscores and dollar signs in identifiers (considered, not adopted)

Neither `_` nor `$` (Phase 11 A25, 2026-09-26), as in `Oberon2.pdf` and voc;
a VMS name like `SYS$QIO` goes in an external procedure's linkage-name
string. The scanner reports one clear error for each use of such a name.

## Project state

Phases 0-10 of `PLAN.md` are complete: poc compiles itself through the LLVM
backend (Stage 1 and Stage 2 reach a fixed point). Phase 11 (settling open design
questions and the TODO backlog) is in progress: `doc/phase-11-inventory.md`
lists every item and its verdict. `PLAN.md` has the roadmap and each phase's
design. `doc/project-history.md` has the account that used to be here,
including what was found while building the front end and `.sym` files
(Phases 0-7), the import search path, `-output-dir`, real `CONST` export and
hidden members in `.sym` files. `src/front/README.md` lists the front-end
modules.
