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
PDF in 2007; a 2022 save changed no text), kept under
`~/Reference/Computer/Languages/Oberon/` with `pdftotext` extracts
`Oberon2-{layout,no-layout}.text`. The original ETH report of October 1993
(`Oberon2-Report.pdf`) and Appendix A of Mössenböck's *Object-Oriented
Programming in Oberon-2* (`oop_in_oberon-2_book.pdf`, an intermediate
state) are background only, for history or an explicit comparison. Where
in doubt about a rule, `Oberon2.pdf`'s wording controls.
`doc/developer/oberon-2-reports.md` describes the four texts and lists where
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
  arm64), and the office machines `erekose` (OpenBSD i386) and `terhali`
  (NetBSD amd64). **Which run when** (user, 2026-09-26): a change is
  checked (`make check` on atla, `gmake check-stage1` on the VMs) on atla,
  cymoril, artos and alerik before it is committed. rackhir (emulated, slow, the only
  non-x86) runs separately on pushed commits, after changes where the
  architecture matters (calls, arithmetic, memory layout, the runtime's C
  calls, the collector) and at each phase's close-out; what it finds is
  fixed in a later commit. voc's programs need `<voc>/lib` on
  `LD_LIBRARY_PATH` except on Linux, and `ssh host cmd` gets neither that
  nor voc on `PATH`, so `test/testenv.sh` sets both (`VOC_BIN_DIR`,
  `VOC_LIB_DIR`).
- **The VAX/VMS development system** (Phase 15 on; the user, 2026-10-05): a
  SIMH `microvax3900` on atla running VMS 5.5-2H4 with UCX, at
  `192.168.2.20` while SIMH runs. The unprivileged user `poc` (home
  `DUA1:[USERS.POC]`) has telnet and FTP. **Its password is in the user's
  `~/.netrc-poc-vax` (mode 600; not `~/.netrc`, which the user's other VAX
  needs, since 2026-10-08), never in the repo or a command line, and is
  never to be printed**: `curl --netrc-file ~/.netrc-poc-vax -P -
  ftp://192.168.2.20/` lists the home directory. FTP works only in **active mode** (curl's `-P -`; in `ftp`,
  turn passive off first), and text must go in **ASCII mode** (curl's
  `--use-ascii`), or VMS stores it as fixed 512-byte records. In the user's tmux, window 7 is the console
  for this work, a telnet session logged in as `POC`, and window 8 runs
  SIMH itself, the VAX's operator console. DCL commands may be typed into
  window 7 (`tmux send-keys`; the user, 2026-10-05), kept to `POC`'s own
  directory; never type into window 8 unless the user asks.
- CLI: `voc options {files {options}}`. Options before the first file apply
  to all files, options after a file apply only to that file, and repeating
  a flag toggles it.

**Size models.** Under `-O2` (the default) `SHORTINT`/`INTEGER`/`LONGINT`
are 8/16/32 bits. Under `-OC` (Component Pascal sizes) they are 16/32/64.
`SET` is 32 bits under both: `Features.md` says 64 for `-OC`, but `OPM.Mod`
says 4 bytes, and poc follows the source. poc models the same two for the
programs it compiles (`-O2`/`-OC` flags, default `-O2`; `MemoryLayout.Mod`).

**How poc itself is built.** `tools/bootstrap/stage0` builds poc with voc
`-OC`, and Stage 1/2 stay at `-OC`: poc needs an 8-byte `LONGINT`
(`Types.Value.intVal`, the constant folder, `DecimalToDouble`). poc's own
source stays strict `Oberon2.pdf` (`make check-strict`, part of `make
check`) and must also type-check under `-O2` (`doc/history/project-history.md`,
"poc's own source under `-O2`"). Without voc, Stage 0 is built by
`BOOTSTRAP_POC` or from a release tarball's `seed/` (`doc/history/phases/phase-13.md`,
steps 4-5: `make seed`, `check-seed`, `dist`, `distcheck`).

**voc's extensions beyond the report** (mostly in `Features.md`). Assume none of them
for poc unless it adopted them:

- `HUGEINT`, `SYSTEM.ADDRESS`, `SYSTEM.INT8/16/32/64`, `SYSTEM.SET32/64`:
  adopted, with poc's own rules (see "Language extensions beyond
  Oberon2.pdf" below).
- Read-only parameters marked `-` (`PROCEDURE P(x-: T)`: passed by
  reference, not assignable; Oakwood 5.13, which recommends against it; not
  in `Features.md`, only in voc's `OPP.Mod`): adopted, taking any
  expression, as voc's does not (see "Read-only parameters" below).
- Pointers start NIL (`-p`, on by default), as `Oberon2.pdf` says too.
- Run-time checks: `-a` (assert), `-t` (type guard) and `-x` (index) are on
  by default, `-r` (range) is off.

**Which of voc's options poc has** (Phase 12 step 1, decided with the user
2026-09-27; `doc/developer/voc-options.md` has the table, option by option): `-r` is
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
C++ API: on atla Fedora's 22.1.8 (host triple `x86_64-redhat-linux-gnu`),
on the BSDs their plain `clang` (19 on OpenBSD and FreeBSD, 21 on NetBSD).
`doc/developer/llvm-toolchain.md` has the full account; what matters most:

- One `.ll` and one `-fPIC` object per module. Each defines
  `<M>.-key.<O2|OC>.<hash of its .sym>` and `<M>.-target.<triple>` and
  refers to its imports' keys, so an importer links only with the
  interface it was compiled against.
- Every emitted `.ll` sets its own `target datalayout` (`LLVMTypes.
  DataLayout`) and `target triple`; without them clang silently uses the
  host's. 32-bit x86 BSDs also get `override-stack-alignment` = 16 and
  `"stackrealign"` on `@main` (`LLVMTypes.NeedsStackRealignment`).
- Libraries (`src/driver/Libraries.Mod`): `poc -library`; the path is
  `-library-path`, `POC_LIBRARY_PATH`, `<poc's dir>/../lib/poc`. `make`
  builds `rtl/llvm` as `poc-rtl`; the bootstrap stages compile it from
  source. A library from another poc version is refused.
- `<M>.c` beside `<M>.Mod` is the module's part in C, compiled and linked
  with it (`rtl/llvm/Platform.c`).
- `src/driver/Version.Mod` holds the version, `tools/build-info` the
  commit. `make install`/`uninstall`; `make check-install`, `check-opt2`
  and `check-lto` are not part of `make check`.
- `make doc` writes the guides, poc(1) and `doc/developer/` as HTML and
  PDF in `build/doc` (pandoc from GFM, xelatex, `tools/doc/pdf.lua`;
  mandoc and groff for poc(1)); `make dist` puts them in the tarball, and
  `make install` installs only the guides' and poc(1)'s. A
  `<placeholder>` outside backquotes is lost as HTML, on GitHub too:
  write `\<placeholder\>`.
- `-opt` defaults to 2, but 0 for 32-bit x86 (x87 reals); `-O2`/`-OC` are
  size models, not optimization levels.
- `llc` is a debugging aid only (`llc <file>.ll -o <file>.s`).

### voc bugs that affect building poc

Bugs in voc 2.1.0 that reach poc's own source or Stage 0, each with the
workaround poc uses, are in `doc/developer/bootstrapping-with-voc.md`. Check there
before puzzling over an error that looks bogus, and keep the workarounds:

- A procedure calling itself from inside its own `WITH` branch gets a false
  "incompatible assignment" error.
- An integral `LONGREAL` literal >= 2^31 (`1.0D10`) gets "Value out of range".
- A `REAL` literal with exponent 38, or a `LONGREAL` one with 308, gets
  "number too large".
- `LONG(SHORT(x))` is folded to `x`.
- `DIV`/`MOD` go wrong near `MIN(LONGINT)` under `-OC`.
- `Files` renames a file by a name relative to the directory current when
  it was opened, and `Files.Delete` fails on an open file.
- The collector misses a pointer held only in a callee-saved register
  (Stage 0 is linked with `tools/bootstrap/voc-heap-gc-spill.c`).

Every voc bug found so far, with reproducers and fixes, is in the separate
vishap-bugs repository (`~/Repos/Oberon/vishap-bugs`); a note in poc's
source or tests that voc does otherwise cites its issue number
("vishap-bugs 18").

## Language extensions beyond Oberon2.pdf

`doc/developer/language-extensions.md` holds the full text of every section below:
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
`LONGINT`; it and any integer type of its width include each other. Also: `ADR`, `GET`, `PUT`, `VAL`, `MOVE`, `BYTE` (a parameter
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
SYSTEM.ADDRESS): SYSTEM.ADDRESS;`. `"VMS"` is lowered by the VAX backend only
(Phase 15 step 5), which refuses `"C"`.

### `-strict` (decided and implemented, Phase 11 B2, 2026-09-25)

`poc -strict` makes each extension above an error in the command-line module's
own source (not in its imports). `make check-strict`, run by `make check`,
applies it to all of `src/`. Found with it and fixed for everyone: a guard,
`IS` or `WITH` on a pointer must name a pointer type, and `=`/`#` compare only
related pointers and procedure values of one type.

### Read-only parameters (decided and implemented, 2026-10-05)

voc's `x-` formal parameter (by reference, read-only; Oakwood 5.13 recommends
against it), adopted with the user 2026-10-05 for `OutStr`/`InStr` (`PLAN.md`,
"Ongoing library enhancements" and "Ongoing language enhancements"). poc's
takes any actual - a variable, a constant (a string included), or another
expression - where voc's takes only a variable (err 122). Assigning to it, or
passing it as a `VAR` actual or a `VAR` receiver, is a compile-time error;
`x*` and `VAR x-` are errors. One of at most 16 bytes is passed by value, a larger one
or an open array by reference, decided from the formal's type alone; as in
Ada, a program may not rely on which. `-strict` rejects the mark, and poc's
own source does not use it.

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

### Record and array literals (decided and implemented, Phase 14, 2026-10-03)

`Point{x := 1, y := 2}`, `Vector{1, 2, 3}`: a named record or fixed array
type and its elements, record ones named, array ones positional or indexed
(`[48..57]: 1`, labels as a `CASE`'s, each index once); a nested
literal may leave out its type name. Made as a variable is (zeroed, every
default), then the elements assigned in the order written. No literal of a
type with a field hidden or read-only where it is written. `CONST origin* =
Point{x := 0, y := 0}` when every element and omitted default is constant:
read-only, folded through selectors, written whole to the `.sym` file, as
are constant field initializers. `-strict` rejects it. The LLVM backend
makes a literal in a stack slot of the function's entry block; a structured
constant is a private constant global of each module that uses it.

## Project state

Phases 0-15 of `PLAN.md` are complete (records in `doc/history/phases/` and
`doc/history/phase-11-inventory.md`): poc compiles itself through the LLVM backend
(Stage 1 and Stage 2 reach a fixed point), and **Peaseblossom 0.1.0 was
released on 2026-10-03** (tag `v0.1.0`, a GitHub release with the tarball
and packages for Fedora, FreeBSD, OpenBSD and NetBSD; Phase 13: `make
install`, the seed, `make dist`, `doc/users-guide.md`,
`doc/reference-guide.md`, `doc/poc.1`, `packaging/`; `doc/developer/DEVELOPER.md`
says how a release is made). Phase 14 added record and array literals
and structured constants (closed 2026-10-04; `doc/history/phases/phase-14.md`),
released with four fixes as **Peaseblossom 0.2.0 on 2026-10-04** (tag
`v0.2.0`, made as `doc/developer/DEVELOPER.md` section 7 says). Read-only
parameters, `OutStr` and `InStr`, and one fix, from `PLAN.md`'s
"Ongoing" sections, were released as **Peaseblossom 0.3.0 on
2026-10-05** (tag `v0.3.0`; the record is in `PLAN.md`, "Peaseblossom
0.3.0"), and **0.3.1** followed the same day with one fix (`-install-library`
over a copy an older poc wrote; tag `v0.3.1`). Libraries that record
their link arguments, C++ parts, a complete `-help`, the documents as
HTML and PDF, and a fix were released as **Peaseblossom 0.4.0 on
2026-10-06** (tag `v0.4.0`; the record is in `PLAN.md`, "Peaseblossom
0.4.0"), and **0.4.1** followed the same day with one fix (`ORD` of a
`SET` under `-OC`; tag `v0.4.1`).
Phase 15, the VAX/VMS MACRO-32 backend, writes MACRO-32 for Phase 8's
slice, each fixture reviewed by the user, assembled and mostly run on the
SIMH VAX (closed 2026-10-08, on the `vax` branch;
`doc/history/phases/phase-15.md`). Phase 16, running on VAX/VMS, is
next; 15-18 are the VAX/VMS work, 19 further extensions, 20 voc's library modules. Bugs found by using
poc on other programs are fixed as they come (`PLAN.md`, "Ongoing bug
fixing"), and the runtime-library additions and language extensions it
shows are wanted are made the same way (`PLAN.md`, "Ongoing library
enhancements" and "Ongoing language enhancements"). The phases were renumbered twice on 2026-10-02, and older
records keep the old numbers (`PLAN.md`, Phase 13).
`doc/history/project-history.md` has the earlier account; `src/front/README.md`
lists the front-end modules.

The User's Guide's examples are files under `doc/examples/`, checked by
`tools/guide-examples` (fixture `doc-users-guide`): change one with the
guide, and run `tools/guide-examples update` after a change to what poc
prints. The Reference Guide's runtime chapter is generated from `rtl/llvm`
by `tools/rtl-reference` (fixture `doc-reference-guide`): after changing a
runtime module's interface or comments, run `tools/rtl-reference update
doc/reference-guide.md rtl/llvm <scratch dir>` with `build/bin` on `PATH`.
