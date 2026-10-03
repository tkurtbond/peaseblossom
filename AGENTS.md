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

**`Oberon2.pdf` is the authoritative spec for Peaseblossom**: the later
revision of the Oberon-2 report by H. Mössenböck and N. Wirth (exported to
PDF in 2007, modified again in 2022), kept under
`~/Reference/Computer/Languages/Oberon/` with `pdftotext` extracts
`Oberon2-{layout,no-layout}.text`. The original ETH report of October 1993
(`Oberon2-Report.pdf`) and Appendix A of Mössenböck's *Object-Oriented
Programming in Oberon-2* (`oop_in_oberon-2_book.pdf`, an intermediate
state) are background only, for history or an explicit comparison. Where
in doubt about a rule, `Oberon2.pdf`'s wording controls.
`doc/oberon-2-reports.md` describes the three texts and lists where
`Oberon2.pdf` differs from 1993, all in one direction: pointers start NIL
(§6.4), forward declarations need "identical" parameter lists (§10),
`Trees.Init` becomes `NewTree`, an `ARRAY OF CHAR` parameter matching a
string must be a value parameter (Appendix A), `ASSERT` is gone (only
`HALT(x)`), and the FOR statement evaluates its start value first and
types its bounds by compatibility (§9.8).

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
  `artos` (NetBSD amd64), `alerik` (FreeBSD amd64) and `rackhir` (FreeBSD
  arm64), and the office
  machines `erekose` (OpenBSD i386) and `terhali` (NetBSD amd64). **Which
  run when** (user, 2026-09-26): a change is checked (`make check`, and
  `gmake check` on each VM) on atla, cymoril, artos and alerik (since
  2026-09-27) before it is committed.
  rackhir is emulated arm64, so slow; it is the only non-x86 machine and
  runs as a separate stream, on commits already pushed: after changes where
  the architecture matters (code for calls, arithmetic and memory layout,
  the runtime's C calls, the collector) and at each phase's close-out. What
  it finds is fixed in a later commit. Programs
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
Without voc (Phase 13 step 4), `tools/bootstrap/stage0` builds Stage 0
with `BOOTSTRAP_POC` (a poc already built), or from `seed/`, poc's own IR
for 64-bit or 32-bit x86 BSD hosts, which `make seed` writes and only a
release tarball carries (not git; `make seed` writes `build/seed`); a
tarball builds from its seed even where voc is. `make check-seed` checks it
gives the same Stage 1. `make dist` (Phase 13 step 5) writes the tarball
from a clean HEAD, `make distcheck` builds it without voc and runs
`check-install`.

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

**Which of voc's options poc has** (Phase 12 step 1, decided with the user
2026-09-27; `doc/voc-options.md` has the table, option by option): `-r` is
`poc -range-checks`, `-M` is `-static`, `-V` is `-verbose` (the clang command),
and `-link <arg>` stands for voc's `LDFLAGS`/`LDLIBS`. `-S` and `-m` are
`-emit-llvm-ir` and `-build`; `-c` is `-compile` (step 2f). poc's checks
cannot be turned off (`-a`, `-t`, `-x`, `-p`); `-e`/`-s`/`-F`, `-f`, `-OV` and
`-A..` do not apply.

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
(bitsavers), and how to fetch it (a browser-like `User-Agent`); so far only
the calling standard (`AA-LA66B`) and the Linker manual with the object
language (`AA-LA62A`) are downloaded.

## Toolchain: LLVM (clang/llc)

`LLVMToolchainDriver.Mod` shells out to `clang` rather than linking LLVM's
C++ API. `doc/llvm-toolchain.md` has the full account of each point here.

- **Versions**: atla has Fedora's clang/llc 22.1.8 on `PATH`, host triple
  `x86_64-redhat-linux-gnu`; the BSD hosts' plain `clang` is 19 (OpenBSD,
  FreeBSD) or 21 (NetBSD).
- **One `.ll` and one object per module** (Phase 12 step 2a): each module's
  `_init` runs its body once, after its imports' `_init` in IMPORT-list
  order; `main` calls the runtime's, then the main module's. Each object
  defines `<M>.-key.<O2|OC>.<hash of its .sym>` and `<M>.-target.<triple>`
  and refers to its imports' keys, so an importer links only with the
  interface it was compiled against. Every object is `-fPIC`.
- **Every emitted `.ll` sets its own `target datalayout` and `target
  triple`**: without them clang silently substitutes the host's, which
  would hide a cross-compiling mismatch. The datalayout is the
  architecture's (`LLVMTypes.DataLayout`: x86_64, 32-bit x86, aarch64);
  for one poc has not been run on there is none, and clang uses its own.
  The driver passes `-lm` (`Math`/`MathL` call libm).
- **Libraries** (Phase 12 steps 2c-2f; `src/driver/Libraries.Mod`): `poc
  -library <name> <file>...` builds `lib<name>.a`/`.so`, a manifest and
  per-module `.sym`/`.ll`/`.o` into `<output-dir>/<triple>/<O2|OC>/`. The
  library path is `-library-path`, then `POC_LIBRARY_PATH`, then `<poc's
  dir>/../lib/poc` (`-clear-library-path` drops all three); a module a
  library has is never compiled from source. A module can be given
  without source as its `.sym` and `.o` (or `.ll`); `poc -compile` makes
  them. `make` builds `rtl/llvm` as the library `poc-rtl`; the bootstrap
  stages compile it from source. A manifest records the poc version that
  wrote it, and a library from another version is refused ("rebuild it").
- **Version** (Phase 13 step 1): `src/driver/Version.Mod` is the one place
  the number is kept (0.x.y); `tools/build-info` writes `build/gen/
  BuildInfo.Mod`, the commit (`-dirty` with changed tracked files, empty
  without `.git`), on every `make` and in each bootstrap stage. `poc
  -version` prints both, the target and size model, and clang's version.
- **32-bit x86 BSDs** get the module flag `override-stack-alignment` = 16
  and `"stackrealign"` on `@main` (`LLVMTypes.NeedsStackRealignment`):
  their C libraries assume a 16-byte aligned stack, LLVM does not.
- **A module's part in C** (Phase 12 step 5a): `<M>.c` beside `<M>.Mod` is
  compiled with the module, to `<M>.c.o`, and goes wherever the module's
  object goes, with each `-c-flag <arg>` (Phase 13 step 2). `rtl/llvm/
  Platform.c` is the one: what the four systems spell differently, which
  only their headers know.
- **Installing** (Phase 13 step 3): `make install` (`PREFIX`, `DESTDIR`,
  `BINDIR`, `LIBDIR` = `$(BINDIR)/../lib`, `MANDIR`, `DOCDIR`) installs
  the Stage 2 poc and poc-rtl for the host triple, both size models, each
  also built with `-g` in `<O2|OC>-g/`, which `poc -g` looks in first;
  `make uninstall` removes them; `make check-install` (not part of `make
  check`) installs into a scratch `DESTDIR` and runs `test/install/
  check.sh` with only that poc and clang on `PATH`. An installed
  library's directory is in a program's run-time path only absolutely; a
  symbolic link to poc finds its library.
- **Building a program** (Phase 13 step 2): `poc <file>` is `poc -build
  <file>`, and without `-o` the executable is named after the module, in
  the current directory. `-build`, `-library` and `-compile` say nothing
  on success; `-help` is a short summary on standard output.
- **Options**: `-opt <level>` (default 2, but 0 for 32-bit x86, whose reals
  are x87; not `-O<level>`, which is the size model), `-static`, `-link
  <arg>`, `-verbose`, `-lto` (ignored for 32-bit x86 NetBSD; `make
  check-lto`, not a gate), and `-g` (DWARF for gdb and lldb: procedures,
  lines, parameters, variables, records, arrays, pointers, open arrays;
  claimed as C; fixture `llvm-debug-info`). `make check-opt2` builds
  everything at `-O2`.
- `llc` is **not** in the build path; it is a debugging aid only (`llc
  <file>.ll -o <file>.s`; it has no `-S` flag).

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
`LONGINT`. Also: `ADR`, `GET`, `PUT`, `VAL`, `MOVE`, `BYTE` (a parameter
takes a `CHAR`, a one-byte `SHORTINT`, a `BYTE`, a `VAR` one a `BOOLEAN`
too: Oakwood's rule and voc's, 2026-10-02), `PTR` (opaque:
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
`GarbageCollectedHeap.RegisterFinalizer` (Phase 12 step 5c, voc's `Heap`'s):
a finalizer runs after the collection that finds its object unreachable,
and for every object still registered when the program ends, traps
included (`atexit`).

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
range traps (exit 8). `LEN` of a fixed-length dimension is a constant of type
`LONGINT` but assignable wherever its value fits, and `NIL` is a constant
(2026-10-02, as voc).

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
Any expression; it sees only names declared before its `:=`. `-strict` rejects
it.

### Record field initializers (decided and implemented, Phase 11 D17, 2026-09-26)

`RECORD x, y: INTEGER := e END` - the fields' defaults, assigned (each field
its own evaluation of `e`) whenever a record of the type is made: a variable,
`NEW`, a record inside one; not a copy. Base type's first. Any expression, but
none of a procedure's variables or procedures. Works across modules (`.sym`
writes `:= ..`). `-strict` rejects it.

### What traps, and what does not (Phase 11 C9)

The tables of trap statuses 2-14, what ends a program silently, what nothing
stops, and what is a compile-time error. `poc -trap-location` (C7) prefixes
every trap message with `file:line:column:` and ends it with the procedure,
"(in List.Insert)". Since Phase 12 step 1 (2026-09-27) a function that reaches
its `END` traps (12), a record assigned to a `VAR` parameter or `p^` whose
dynamic type extends its static type traps (13), both always, as the report
requires; `-range-checks` makes `SHORT`/`CHR` of a value that does not fit
trap (14). A bare `RETURN` in a function is a compile-time error.

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

### Underscores and dollar signs in identifiers (decided and implemented, Phase 11 A25, 2026-09-26)

Both, anywhere a letter may be, first included, for VMS names such as
`SS$_NORMAL` and `DSC$W_LENGTH` in modules of constants generated from
STARLET. `-strict` rejects them. The backend's own names contain `-` so they
never match a user's.

### Hexadecimal constants as 64-bit patterns (decided and implemented, Phase 12 step 3, 2026-09-27)

As in voc: a hexadecimal constant of 16 significant digits, the first above
7, is the negative 64-bit value it spells (`0FFFFFFFFD76AA478H` is
-680876936, a `LONGINT`). More digits is an error. `-strict` rejects it.

### Text after the module's end (decided and implemented, Phase 12 step 3, 2026-09-27)

poc reads nothing after the period of `END M.`, as Oberon compilers do: an
Oberon system text keeps its fonts there. Not an extension.

## Project state

Phases 0-12 of `PLAN.md` are complete: poc compiles itself through the LLVM
backend (Stage 1 and Stage 2 reach a fixed point). Phase 11 (settling open
design questions and the TODO backlog) closed on 2026-09-26:
`doc/phase-11-inventory.md` lists every item and its verdict. Phase 12
(library and module support: voc's options, libraries, voc's module
inventory, then voc's runtime modules and finalization) closed on
2026-10-02, `doc/phases/phase-12.md`; the modules under voc's `src/library`
wait for Phase 19. Phase 13 (added 2026-10-02; the later phases renumbered,
old 13-18 now 14-19), next, packages poc: `make install`, a bootstrap seed
that needs no voc, a release tarball, OS packages, a User's Guide, a
Reference Guide and `poc(1)`. `PLAN.md` has the
roadmap and each phase's design. `doc/project-history.md` has the account that used to be here,
including what was found while building the front end and `.sym` files
(Phases 0-7), the import search path, `-output-dir`, real `CONST` export and
hidden members in `.sym` files. `src/front/README.md` lists the front-end
modules.
