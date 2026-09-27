# voc's command-line options, and what poc does with each

`PLAN.md` Phase 12 step 1. Every option voc 2.1.0 accepts, from its usage text
(`voc` with no arguments), `doc/Compiling.md`, `doc/Features.md` and the source
of truth, `OPM.Mod`'s `ScanOptions` (which accepts exactly the options the
usage text lists, and warns "option ... ignored" for any other letter). Each
was probed on atla, 2026-09-27, with the programs described in the last
column's notes. Decisions made with the user the same day.

voc's command line is `voc options {files {options}}`: options before the first
file apply to every file, options after a file only to it, and repeating an
option toggles it. poc compiles one program per run, whole (every import is
compiled from source for the target and size model of the run: Phase 9 step
4a), so it has no per-file options; its flags do not toggle, and a later one
wins.

## The table

| Option | voc's meaning | poc | Why |
|---|---|---|---|
| `-p` | Local pointers start NIL (on by default) | not applicable | Every variable starts at zero in poc, locals included (Phase 11 D16), so pointers and procedure values always start NIL; no switch turns it off. `voc -p` (off) left a local pointer holding a previous call's garbage |
| `-a` | Halt on a failed `ASSERT` (on by default) | not adopted | `ASSERT` is always on (Phase 11 A14, `doc/assert-survey.md`); decided again 2026-09-27: poc has no switch to turn a check off |
| `-r` | Halt on a range failure (off by default): `SHORT` of an integer and `CHR` that do not fit, Halt(-8) "Value out of range" | **adopted as `-range-checks`** | Off by default, as in voc. Traps with status 14 (`SHORT argument out of range`, `CHR argument out of range`). `SHORT` of a `LONGREAL` is not checked, as in voc. voc's `-r` also covers `SHORT` of its larger set types, which poc's `SHORT` does not take. Fixture `llvm-range-checks`. Differs from voc on purpose: `CHR` of a negative value traps, where `voc -r` lets it through (its `__R` macro compares signed; only `__CHRF`, used for an argument with side effects, compares unsigned) |
| `-t` | Halt on a failed type guard (on by default), and on the implicit guard of a record assignment (Halt(-6)) | not adopted | The type guard is always on in poc. The record-assignment check, which poc lacked, is now always on too (status 13, below) |
| `-x` | Halt on an index out of range (on by default) | not adopted | Always on in poc (status 2) |
| `-e` | Allow a new symbol file that only adds to the old one | not applicable | voc refuses by default to compile a module whose exports differ from its existing `.sym` ("B is new, compile with option e"; "A is redefined, compile with option s"), to protect the separately compiled modules that import it. poc never compiles a module against another's stale `.sym`: every whole-program command regenerates each import's `.sym` from its source. What a library's `.sym` must promise its clients is Phase 12 step 2's question |
| `-s` | Allow a new symbol file that changes the old one | not applicable | As `-e` |
| `-F` | Force a new symbol file (for a module named like an installed library module) | not applicable | As `-e`; poc always writes the `.sym` |
| `-m` | This module is the main program; link dynamically | already covered | `poc -o <exe> -build <file>`: the file named is the main module, always |
| `-M` | This module is the main program; link statically | **adopted as `-static`** | voc passes the C compiler `-static` (on every Unix but Darwin), so the whole executable is static, libc included. `poc -static` makes `-build` pass `clang -static`; checked on Linux (needs `glibc-static`), OpenBSD i386 (a static PIE, no program interpreter), NetBSD amd64 and FreeBSD arm64. Fixture `poc-link-flags` |
| `-S` | Do not call the C compiler | already covered | `poc -emit-llvm-ir`: each module's IR in a `.ll` of its own (since Phase 12 step 2a; before, the whole program's in one), no clang |
| `-c` | Do not link | `-compile` (step 2f) | Since Phase 12 step 2a poc, like voc, compiles each module to its own object file. Step 2's design first gave `-c` no flag (`-library` compiles without linking a program); step 2f added `poc -compile <file>...`, which writes each named module's `.sym`, `.ll` and `.o` with no `main`, so a module can be given to others as its `.sym` and `.o` |
| `-f` | No VT100 control characters in status output | not applicable | poc's output has no color or control characters |
| `-V` | Verbose: the sizes of the size model, and the C compiler's commands | **adopted as `-verbose`** (the commands) | `-build` prints the clang command it runs, on stderr. The size model needs no line of its own: it is `-O2` or `-OC` on poc's own command line |
| `-O2` | Size model: 8/16/32-bit `SHORTINT`/`INTEGER`/`LONGINT`, 32-bit `SET` (default) | already covered | poc's `-O2`, default |
| `-OC` | Size model: 16/32/64, 32-bit `SET` | already covered | poc's `-OC` |
| `-OV` | Size model: 8/32/64, 64-bit `SET` | not adopted | Nothing to compare with: the voc installation has neither `V/` symbol files nor `libvoc-OV`, so `voc -OV` cannot compile a program that imports anything (err 152), and a module alone fails to link (`-lvoc-OV`). A 64-bit `SET` is `SYSTEM.SET64` in poc |
| `-A44`, `-A48`, `-A88` | Address size and alignment of the C compiler's target | not applicable | Decided 2026-09-20 (`PLAN.md` Phase 12 step 1): poc's `-target <triple>` fixes both through the triple's data layout |

voc also reads the environment: `OBERON` and `MODULES` (its symbol-file search
path; poc's is `POC_IMPORT_PATH` and `-import-path`), and `CFLAGS`, `LDFLAGS`
and `LDLIBS`, added to its C compiler's command. For the last two poc has
**`-link <arg>`**, repeatable: each argument is passed to clang as one word
(single-quoted), after the program's objects and before `-lm`, so a program with
`["C"]` procedures can link a C library other than libc and libm (`-link -lz`,
`-link -L<dir>`), which it could not before. Fixture `poc-link-flags` builds a
static C library into a directory whose name has a space and links it both
ways.

## What the triage found missing in poc

Probing voc's switches turned up checks voc makes that poc did not, both of
them rules of `Oberon2.pdf`. Decided with the user 2026-09-27: both always on,
like poc's other checks.

- **A function procedure that reaches its `END`** (§10.1, "Function procedures
  must be left via a return statement"). voc halts always (Halt(-3), "Reached
  end of function without reaching RETURN"); poc returned a zero of the result
  type. Now status 12, `function procedure reached its END without RETURN`,
  located at the `END` under `-trap-location`. Fixture `llvm-return-trap`.
- **A record assigned to a variable whose dynamic type is an extension of its
  static type** (§9.1, "the dynamic type of v must be the same as the static
  type of v"; Appendix A, assignment compatibility rule 3). Only a `VAR`
  parameter of record type (a receiver included) and `p^` can have such a
  dynamic type. voc halts under `-t` (Halt(-6), "Implicit type guard in
  record assignment failed"); poc copied the static type's fields and left
  the extension's as they were. Now status 13, `record assigned to a variable
  whose dynamic type extends its static type`: one comparison of the target's
  type tag with its static type's before the copy. A record with no name of its
  own cannot be extended and is not checked. Fixture `llvm-record-assign-trap`.

Found on the way:

- **A bare `RETURN` in a function procedure** compiled (the backend returned a
  zero); voc rejects it (err 124). Now a compile-time error, `RETURN in a
  function procedure needs a value`. Fixture `semantic-reject-bare-return`.
- **A whole-record assignment to a `VAR` parameter narrowed by `WITH`** used
  the parameter's declared type, so `WITH v: S DO v := t END` copied only the
  base record's fields (voc: all of `S`'s). Fixed; case 0 of
  `llvm-record-assign-trap`.
- **A type guard as an assignment target**, `v(S) := t`, which the report's
  grammar allows (`Designator = Qualident {... | "(" Qualident ")"}`), is a
  syntax error in poc: the parser takes `v(S)` for a call. voc accepts it but
  its generated C does not compile (`incompatible types when assigning to
  type 'R' from type 'S'`). Not fixed here: `000-todo.org`.
