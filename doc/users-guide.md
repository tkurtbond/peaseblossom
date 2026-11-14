# The Peaseblossom User's Guide

Peaseblossom is a compiler for Oberon-2. Its command is `poc`, the
Peaseblossom Oberon Compiler. It compiles each module to native code through
LLVM, by way of `clang`, and runs on Linux, FreeBSD, NetBSD and OpenBSD, on
x86_64, 32-bit x86 and (FreeBSD) arm64.

The language is the one of *The Programming Language Oberon-2*, H. Mössenböck
and N. Wirth, in its later revision (`Oberon2.pdf`; "the report" below), with
a few extensions, each of which `poc -strict` turns off. This guide is about
using poc. The *Reference Guide* (`doc/reference-guide.md`) says exactly what
poc accepts and does, and `poc(1)` lists every option.

Every program in this guide is a file under `doc/examples`, and every session
shown with a `$` prompt is run by poc's test suite (`tools/guide-examples`),
which fails when what the guide shows is not what poc does.

## Contents

1. Installing
2. A first program
3. Building programs
4. Modules and where poc finds them
5. Libraries
6. Checking a module without building it
7. When a program fails
8. Debugging
9. Calling C
10. The runtime modules
11. Coroutines
12. Coming from voc
13. poc on VAX/VMS

## 1. Installing

`INSTALL.md`, at the top of the source tree, says how to build and install
poc: from a release tarball, which needs only clang and GNU make, from the
git repository, and into `/usr/local` (the default) or anywhere else. In
short:

    make installable           # gmake on the BSDs
    make install               # as root, or with PREFIX=$HOME/local

poc needs `clang` on `PATH` whenever it builds a program: it writes LLVM
IR, and clang compiles and links it. Any clang from 19 on does; on the BSDs
it is the system's (OpenBSD and FreeBSD) or pkgsrc's (NetBSD).

An installed poc is `$(BINDIR)/poc`, with its runtime, the library
`poc-rtl`, in `$(LIBDIR)/poc/<triple>/`: `O2/` and `OC/` for the two size
models (section 3), and `O2-g/` and `OC-g/`, built with debug information,
which `poc -g` uses (section 8). poc finds its runtime as `../lib/poc` from
the directory it is in, following symbolic links, so a link to poc from
anywhere works.

`<triple>` is clang's default target when poc was built, and poc builds for
clang's default target now (`poc -version` prints both). If they differ,
poc finds none of its runtime: every import of `Out` or another runtime
module is an error, with a note that `poc-rtl` has the module, but for the
other target. On NetBSD this happens when pkgsrc's clang comes from another
NetBSD release's packages than the system's (INSTALL.md, section 1).

## 2. A first program

<!-- example: hello/Hello.Mod -->
```
MODULE Hello;
  IMPORT Out;
BEGIN
  Out.String("Hello, world"); Out.Ln
END Hello.
```

`poc` with a file builds a program: the file's module is the main module,
and its body is the program.

<!-- run: hello -->
```
$ poc Hello.Mod
$ ./Hello
Hello, world
```

poc says nothing when it succeeds. The executable is named after the module,
in the current directory; `-o` names it otherwise.

## 3. Building programs

**What a build leaves.** Each module of the program is compiled to three
files in the current directory: `<Module>.sym`, its interface; `<Module>.ll`,
its LLVM IR; and `<Module>.o`. `-output-dir <dir>` puts them there instead
(and makes the directory). The runtime's modules come compiled, from the
library `poc-rtl`, and leave nothing.

<!-- run: hello -->
```
$ poc -o greeting Hello.Mod
$ ls
Hello.Mod
Hello.ll
Hello.o
Hello.sym
greeting
$ ./greeting
Hello, world
```

Every build reads every module of the program from its source again, but
compiles a module's object only when it would differ from the one there:
the `.ll` and the `.o` record a stamp, a hash of the IR and the clang
command, and an unchanged module's object is linked as it is. A module
with a C part also leaves `<Module>.c.o.d`, the files its C was compiled
from, with its stamp. A change to a module's body compiles that module
again; a change to its interface also compiles the modules that import it.
`-rebuild` compiles every object again (Reference Guide, section 8).

**Errors.** An error names the file, the line and the column, says what is
wrong and names what it is about. poc reports every error it finds, then
exits with status 1.

<!-- example: errors/Errors.Mod -->
```
MODULE Errors;
  IMPORT Out;
  VAR count: INTEGER; letter: CHAR;
BEGIN
  count := letter;
  Out.Strng("count");
  Out.Int(total, 0)
END Errors.
```

<!-- run: errors -->
```
$ poc Errors.Mod
Errors.Mod:5:3: error: assignment is not type-compatible: CHAR to INTEGER
Errors.Mod:6:3: error: undeclared identifier: Out.Strng
Errors.Mod:7:11: error: undeclared identifier: total
3 error(s)
```

**Size models.** The report leaves the sizes of the integer types to the
implementation. poc has two, as voc has: `-O2` (the default), where
`SHORTINT`, `INTEGER` and `LONGINT` have 8, 16 and 32 bits, and `-OC`, the
sizes of Component Pascal, where they have 16, 32 and 64. `HUGEINT` has 64
bits and `SET` 32 under both. The unsigned `SHORTCARD`, `CARDINAL`,
`LONGCARD` and `HUGECARD`, an extension, have the same widths as those
four. A program and every module it uses are
compiled under one model, and the runtime is there for both.

<!-- example: sizes/Sizes.Mod -->
```
MODULE Sizes;
  IMPORT Out;
BEGIN
  Out.String("INTEGER: "); Out.Int(SIZE(INTEGER), 0); Out.String(" bytes, MAX ");
  Out.Int(MAX(INTEGER), 0); Out.Ln;
  Out.String("LONGINT: "); Out.Int(SIZE(LONGINT), 0); Out.String(" bytes, MAX ");
  Out.Int(MAX(LONGINT), 0); Out.Ln
END Sizes.
```

<!-- run: sizes -->
```
$ poc Sizes.Mod
$ ./Sizes
INTEGER: 2 bytes, MAX 32767
LONGINT: 4 bytes, MAX 2147483647
$ poc -OC Sizes.Mod
$ ./Sizes
INTEGER: 4 bytes, MAX 2147483647
LONGINT: 8 bytes, MAX 9223372036854775807
```

**Other options for a build.**

- `-opt <level>`: clang's optimization, `0`, `1`, `2`, `3`, `s`, `z` or `g`.
  The default is 2, except on 32-bit x86, where it is 0: there poc's reals
  are the x87's, whose results optimization changes.
- `-static`: a fully static executable (on Linux this needs the C library's
  static version, `glibc-static` on Fedora).
- `-link <arg>`: passes `<arg>` to the link, for a C library a program calls
  (section 9): `-link -lz`, `-link -L/opt/lib`. Repeatable. A library built
  with `-link` records the arguments, and every program that links the
  library gets them. For `vax-dec-vms` each is a line of the Linker's
  options file instead (the *VAX/VMS Guide*, chapter 3).
- `-verbose`: prints each command poc runs.
- `-target <triple>`: builds for another target than the host's, as far as
  clang can (it needs that target's C library to link).
- `-range-checks`, `-trap-location`, `-trap-heap-exhausted`: section 7. `-g`:
  section 8.

Options may come before the file or after it, and apply to the whole
build either way.

## 4. Modules and where poc finds them

A module named in an `IMPORT` is found in this order:

1. in a library on the library path (section 5), compiled already;
2. as `<Module>.Mod` (or `.mod`) in the current directory, then in each
   directory of the *import path*, in order;
3. as `<Module>.sym` with `<Module>.o` (or `.ll`), the same way: a module
   given without its source (below).

The import path is `-import-path <dir>`, repeatable, after the directories of
`POC_IMPORT_PATH` (separated by colons). Only those directories are searched,
not the directories inside them.

<!-- example: project/lib/Shapes.Mod -->
```
MODULE Shapes;
  (* A rectangle and its area: a module of the project's library
     directory, imported by src/Main.Mod *)
  TYPE Rectangle* = RECORD width*, height*: INTEGER END;

  PROCEDURE Area*(r: Rectangle): INTEGER;
  BEGIN RETURN r.width * r.height
  END Area;
END Shapes.
```

<!-- example: project/src/Main.Mod -->
```
MODULE Main;
  IMPORT Out, Shapes;
  VAR r: Shapes.Rectangle;
BEGIN
  r.width := 6; r.height := 7;
  Out.String("area "); Out.Int(Shapes.Area(r), 0); Out.Ln
END Main.
```

<!-- run: project -->
```
$ cd src
$ poc -import-path ../lib Main.Mod
$ ./Main
area 42
```

When poc cannot find a module, it says where it looked: the current
directory, the import path and the library path.

**A module without its source.** `poc -compile <file>...` compiles modules
to their `.sym`, `.ll` and `.o` and links nothing. A module's `.sym` and `.o`
can then be given to others, who build with them as with the source:

<!-- run: project -->
```
$ cd lib
$ poc -compile Shapes.Mod
$ mkdir ../compiled
$ mv Shapes.sym Shapes.o ../compiled
$ cd ../src
$ poc -import-path ../compiled Main.Mod
$ ./Main
area 42
```

poc checks that a `.o` is the one its `.sym` describes, and that each module
was compiled against the interfaces of the modules it imports as they are
now: a program never links a module with a stale view of another.

## 5. Libraries

A library is a set of modules compiled once, for one target and size model,
and used by any number of programs: `lib<name>.a`, a shared library, and a
manifest, `<name>.library`, that lets poc check that the libraries a program
uses agree with each other. The runtime is one, `poc-rtl`.

`poc -library <name> <file>...` builds one. Without `-output-dir` it goes in
`./<triple>/<O2|OC>/`, so a library directory can hold libraries for several
targets and both size models. A program finds it through the *library
path*: `-library-path <dir>`, repeatable, then `POC_LIBRARY_PATH`, then poc's
own `../lib/poc`. A module a library on the path has is always taken from
it, never compiled.
An object file named among a library's files goes into it as well
(section 9).

<!-- example: library/greet/Greet.Mod -->
```
MODULE Greet;
  IMPORT Out;

  PROCEDURE Hello*(name: ARRAY OF CHAR);
  BEGIN Out.String("Hello, "); Out.String(name); Out.Ln
  END Hello;
END Greet.
```

<!-- example: library/app/App.Mod -->
```
MODULE App;
  IMPORT Greet;
BEGIN
  Greet.Hello("library")
END App.
```

<!-- run: library -->
```
$ cd greet
$ poc -library greet Greet.Mod
$ cd ../app
$ poc -library-path ../greet App.Mod
$ ./App
Hello, library
```

A program links a library's archive, so the executable stands alone.
`-shared-libraries` links the shared libraries instead; the executable then
finds each by the directory it was in, absolutely, and, for a library not
installed with poc, relative to the executable as well:

<!-- run: library -->
```
$ cd greet
$ poc -library greet Greet.Mod
$ cd ../app
$ poc -shared-libraries -library-path ../greet -o app-shared App.Mod
$ ./app-shared
Hello, library
```

`poc -install-library <name>` copies a library from the library path into
poc's own `../lib/poc` (or `-output-dir`), where every program finds it
without a `-library-path`. A library records the poc version that built it,
and another version refuses it ("rebuild it"). With `-g`, `-library` builds
a library with debug information beside the plain one, in
`<triple>/<O2|OC>-g/` (section 8).

Some code cannot go into a shared library: a binding to a static library
built without `-fPIC`, for one. Then the shared link fails, and poc says
that `-no-shared-library` builds only the archive:

```
$ poc -no-shared-library -library greet Greet.Mod
```

poc does not do this by itself, since the same failure could be a misspelt
`-link`, and it does not try that link, so a mistake in `-link`'s arguments
is found by the first program to link the library. A library with a shared
library cannot need one without (poc refuses it, naming both), so a library
that needs one built this way must be built this way too; the reverse is
fine. `-shared-libraries` links such a library's archive and warns ("has no
shared library, so its archive is linked"). The program then has its own
copy of those modules, and a plugin it loads sees them only with `-link
-rdynamic`.

## 6. Checking a module without building it

`poc -check <file>` checks a module against the interfaces of the modules
it imports, and writes nothing: "semantic OK", or the errors. An import must
be compiled already, in a library or as its `.sym` file (`poc -compile`
writes one); `-check` compiles no source.

poc accepts a few things the report does not: `HUGEINT`, variable and field
initializers, `ASSERT`, underscores in names and others (the Reference Guide
lists them). `-strict` makes each an error in the module named, so that a
module meant for any Oberon-2 compiler keeps to the report:

<!-- example: strict/Counter.Mod -->
```
MODULE Counter;
  (* A variable initializer, := 0, is one of poc's extensions *)
  IMPORT Out;
  VAR count: INTEGER := 0;
BEGIN
  INC(count); Out.Int(count, 0); Out.Ln
END Counter.
```

<!-- run: strict -->
```
$ poc -check Counter.Mod
semantic OK
$ poc -strict -check Counter.Mod
Counter.Mod:4:22: error: a variable initializer is not in the Oberon-2 report (-strict)
1 error(s)
```

The largest of the extensions is record and array literals: a value of a
record type or a fixed array type, written in an expression after the
type's name. A record's fields are named and an array's elements come in
order; a literal inside another may leave out its type's name; and what a
literal leaves out has its default, as in a new variable. A literal whose
elements are all constant can declare a constant:

<!-- example: literals/Shapes.Mod -->
```
MODULE Shapes;
  (* Record and array literals, and a structured constant: poc's extensions *)
  IMPORT Out;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Line = RECORD from, to: Point; width: INTEGER := 1 END;
    Path = ARRAY 4 OF Point;
  CONST
    origin = Point{x := 0, y := 0};
  VAR line: Line; path: Path; i: INTEGER;
BEGIN
  line := Line{from := origin, to := Point{x := 3, y := 4}};
  Out.Int(line.to.x, 0); Out.Int(line.to.y, 2); Out.Int(line.width, 2); Out.Ln;
  path := Path{{x := 1, y := 1}, {x := 2, y := 4}, {x := 3, y := 9}};
  FOR i := 0 TO LEN(path) - 1 DO Out.Int(path[i].y, 2) END; Out.Ln
END Shapes.
```

<!-- run: literals -->
```
$ poc Shapes.Mod
$ ./Shapes
3 4 1
 1 4 9 0
```

## 7. When a program fails

**Traps.** What the report calls an error at run time stops the program: it
writes what happened on standard error and exits with a status of its own.

| Status | What |
|---|---|
| 2 | an index out of range |
| 3 | a `CASE` with no matching label and no `ELSE` |
| 4 | a NIL pointer dereferenced, or a NIL procedure called |
| 5 | a type guard that fails |
| 6 | a `WITH` with no matching guard and no `ELSE` |
| 7 | `NEW` of an open array with a length that is not positive |
| 8 | `ENTIER` of a value no `LONGINT` holds |
| 9 | an open array assigned to an array too short for it |
| 10 | a failed `ASSERT` |
| 11 | with `-trap-heap-exhausted`: a `NEW` the heap cannot satisfy |
| 12 | a function procedure that reaches its `END` |
| 13 | a record assigned to a variable whose dynamic type extends its static type |
| 14 | with `-range-checks`: `SHORT`, `CHR` or predeclared `VAL` of a value that does not fit |

<!-- example: traps/Lookup.Mod -->
```
MODULE Lookup;
  IMPORT Out;
  VAR table: ARRAY 4 OF INTEGER; i: INTEGER;

  PROCEDURE Get(i: INTEGER): INTEGER;
  BEGIN RETURN table[i]
  END Get;

BEGIN
  FOR i := 0 TO 3 DO table[i] := i * i END;
  Out.Int(Get(3), 0); Out.Ln;
  Out.Int(Get(4), 0); Out.Ln
END Lookup.
```

<!-- run: traps -->
```
$ poc Lookup.Mod
$ ./Lookup; echo "exit status $?"
9
index out of range
exit status 2
```

The message does not say where. `-trap-location` makes every trap name its
file, line and column, and the procedure it is in:

<!-- run: traps -->
```
$ poc -trap-location Lookup.Mod
$ ./Lookup
9
Lookup.Mod:6:22: index out of range (in Lookup.Get)
```

**Range checks.** `SHORT` and `CHR` keep the low bits of a value that does
not fit, as voc does; `-range-checks` makes that a trap:

<!-- example: traps/Narrow.Mod -->
```
MODULE Narrow;
  IMPORT Out;
  VAR big: INTEGER; small: SHORTINT;
BEGIN
  big := 300; small := SHORT(big);
  Out.Int(small, 0); Out.Ln
END Narrow.
```

<!-- run: traps -->
```
$ poc Narrow.Mod
$ ./Narrow
44
$ poc -range-checks Narrow.Mod
$ ./Narrow; echo "exit status $?"
SHORT argument out of range
exit status 14
```

**What does not trap.** Integer arithmetic wraps around at its type's width:
that is a promise. Real arithmetic follows IEEE 754 and gives infinities and
NaNs without stopping. `HALT(n)` ends the program with status `n`, 0 to 255,
and says nothing. Integer division by zero is not checked: on x86 the
processor stops the program (`SIGFPE`, status 136 in a shell), on arm64 it
gives a value. A `NEW` the heap cannot satisfy leaves the pointer NIL, unless
`-trap-heap-exhausted` makes it trap. Unbounded recursion ends with
`SIGSEGV`. The Reference Guide has the whole table.

## 8. Debugging

`-g` builds a program with debug information that gdb and lldb read: the
procedures and the lines of each module, their parameters and variables,
records, arrays (open ones too) and pointers. It goes best with `-opt 0`, so
that each line's code is where the debugger expects it. Under `-g` the
program links the copy of the runtime that has debug information too, so a
debugger follows a call into `Out` or `Files`; other programs link the plain
one, which is smaller.

<!-- example: debug/Average.Mod -->
```
MODULE Average;
  IMPORT Out;
  VAR marks: ARRAY 5 OF INTEGER; i, sum: INTEGER;
BEGIN
  FOR i := 0 TO 4 DO marks[i] := 60 + i * 5 END;
  sum := 0;
  FOR i := 0 TO 4 DO sum := sum + marks[i] END;
  Out.String("average "); Out.Int(sum DIV 5, 0); Out.Ln
END Average.
```

<!-- run: debug -->
```
$ poc -g -opt 0 Average.Mod
$ ./Average
average 70
```

A session in gdb (shown, not run by the test suite):

    $ gdb -q ./Average
    (gdb) break Average.Mod:7
    Breakpoint 1 at 0x4005d2: file Average.Mod, line 7.
    (gdb) run
    Breakpoint 1, Average_init () at Average.Mod:7
    7	  FOR i := 0 TO 4 DO sum := sum + marks[i] END;
    (gdb) print marks
    $1 = {60, 65, 70, 75, 80}
    (gdb) print sum
    $2 = 0

A module's body is the procedure `<Module>_init`; a procedure `P` of module
`M` is `M.P`. The debugger takes the program for C, so it shows values as C
would (a `CHAR` as a character code and its character, a `BOOLEAN` as 0 or
1).

## 9. Calling C

**A C function.** A procedure declared with `["C"]` and no body is a C
function; a second string gives its C name, when that is not the Oberon one.
A C `int` is `SYSTEM.INT32` and a `size_t` or a pointer `SYSTEM.ADDRESS`,
under both size models (a `LONGINT` is 4 bytes under `-O2` and 8 under
`-OC`, so it matches neither everywhere). The C library and the maths library
are linked always; `-link` adds others.

<!-- example: cfunc/Absolute.Mod -->
```
MODULE Absolute;
  (* abs from the C library: C's int is SYSTEM.INT32 under both size models *)
  IMPORT SYSTEM, Out;

  PROCEDURE ["C", "abs"] CAbs(x: SYSTEM.INT32): SYSTEM.INT32;

BEGIN
  Out.Int(CAbs(-42), 0); Out.Ln
END Absolute.
```

<!-- run: cfunc -->
```
$ poc Absolute.Mod
$ ./Absolute
42
```

**A C function's address.** A C function that takes another's address,
such as `qsort` its comparison, is given it as `SYSTEM.VAL(SYSTEM.ADDRESS,
P)`, where `P` is the other, declared `["C"]`: `Sort(SYSTEM.ADR(a),
LEN(a), SIZE(SYSTEM.INT32), SYSTEM.VAL(SYSTEM.ADDRESS, CompareIntegers))`.
An external procedure is not otherwise a value, and nothing checks that
the function can call it as it will.

**A C variable.** A declaration of a module's `VAR` section that starts
with `["C"]` is a C variable, defined by C and used in place: `VAR ["C",
"environ"] environment-: SYSTEM.ADDRESS;` (a second string gives its C
name, and the declaration then has one identifier) or `VAR ["C"] opterr,
optind: SYSTEM.INT32;`. poc does not zero it: it has the value C gave
it. Its type may not hold a `POINTER TO`, since the collector does not
look in it. A variable that is a macro or thread-local in C, such as
`errno`, or named differently on each system, such as `stdin`, is reached
through a function in the module's part in C instead.

**A module's part in C.** A file `<Module>.c` beside `<Module>.Mod` is
compiled with the module and linked wherever the module is, into a program
or a library: the module's own C, which its `["C"]` procedures call.
`-c-flag <arg>` passes `<arg>` to clang when it compiles it (`-c-flag
-I/opt/include`). The part may be C++ instead, `<Module>.cpp`, compiled by
clang++; a program or library with a C++ part is linked by clang++, which
adds the C++ runtime. A module has one part, not both.

**Threads.** A poc program has one thread, and must not start another,
whether from its C part or by a C library that calls back into Oberon on
a thread of its own. The collector looks for pointers only on the main
thread's stack, so it would free what another thread holds; the heap has
no locks, so `NEW` on two threads at once corrupts it; and `Out`, `Files`
and the other runtime modules keep state that two threads would break. A
C library may run threads of its own as long as none of them runs Oberon
code or uses what the Oberon heap holds. A signal handler is not a
thread, but it interrupts like one: chapter 10, "Signals", has its rule.

A library wrapping a native one, say `fltk`, is built with the `-link`
arguments that native library needs, `poc -link -lfltk -library fltk
...`; its manifest records them, so a program that uses the library,
directly or through another library, is linked with them without naming
them, and with clang++ if the library has a C++ part.

**An object file.** An object compiled some other way, from C, assembly
or anything else, is named among the files of a build or a library:
`poc Main.Mod twice.o`, `poc -library twice Twice.Mod twice.o`. A file
ending in `.o` with no `.sym` beside it is one. A program links it after
its modules' objects and before the libraries and `-link`'s arguments; a
library puts it in its archive and its shared library, so it must be
compiled position-independent (`clang -c -fPIC`), and a C++ one needs
`-link -lstdc++`. An archive keeps one member of a name, so a library
refuses an object named like one of its modules' objects (`Twice.o`,
`Twice.c.o`) or like another object. Other commands refuse an object, and
`-build` refuses a module's own `.o`, which it finds through the import
path.

<!-- example: cpart/hash/Hash.Mod -->
```
MODULE Hash;
  (* FNV-1a, computed by the module's C part, Hash.c beside this file *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "hash_fnv1a"] Fnv1a(s, n: SYSTEM.ADDRESS): SYSTEM.INT32;

  PROCEDURE Of*(s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0; WHILE s[n] # 0X DO INC(n) END;
    RETURN Fnv1a(SYSTEM.ADR(s), n)
  END Of;
END Hash.
```

<!-- example: cpart/hash/Hash.c -->
```
#include <stddef.h>
#include <stdint.h>

int32_t hash_fnv1a(const unsigned char *s, size_t n) {
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < n; i++) { h ^= s[i]; h *= 16777619u; }
  return (int32_t)h;
}
```

<!-- example: cpart/Digest.Mod -->
```
MODULE Digest;
  IMPORT Out, Hash;
BEGIN
  Out.Hex(Hash.Of("Oberon"), 8); Out.Ln
END Digest.
```

<!-- run: cpart -->
```
$ poc -import-path hash Digest.Mod
$ ./Digest
F3AE37DE
```

## 10. The runtime modules

Every program can import these; they are the library `poc-rtl`. Most are
voc's modules of the same names, written again for poc; where one differs
from voc's, its source's first comment says how.

| Module | What it has |
|---|---|
| `Out` | writing to standard output: `String`, `Char`, `Int`, `Hex`, `Real`, `LongReal`, `Ln` |
| `Err` | the same, to standard error |
| `Console` | as `Out`, unbuffered |
| `In` | reading standard input: `Int`, `LongInt`, `Real`, `Char`, `String`, `Name`, `Line`; `Done` says whether it worked |
| `OutStr` | `Out`'s `String`, `Char`, `Int`, `Hex`, `Real`, `LongReal`, `Ln`, appending to a string (poc's own) |
| `InStr` | `In`'s procedures reading a string from a position, which each moves on (poc's own) |
| `Strings` | `Length`, `Append`, `Insert`, `Delete`, `Replace`, `Extract`, `Pos`, `Cap`, `Match` |
| `Math`, `MathL` | `REAL` and `LONGREAL` functions: `sqrt`, `exp`, `ln`, `sin`, `arctan2`, `power`, `round` and the rest |
| `Files` | files: `Old`, `New`, `Register`, `Close`, `Delete`, `Rename`, and riders to read and write bytes, numbers and strings |
| `Modules` | the program's arguments (`ArgCount`, `GetArg`, `GetIntArg`), its modules, and `Halt` |
| `Args` | voc's V4 `Args`: the arguments (`argc`, `Get`, `GetInt`, `Pos`) and the environment (`GetEnv`, and `getEnv`, which says whether a variable is set at all) |
| `Platform` | the system underneath: the environment, the clock, `System`, file descriptors |
| `Texts`, `Oberon` | voc's texts, and the stub of the Oberon system's module: `Oberon.Log` writes to standard output, `Oberon.Par` has the arguments |
| `Reals` | converting reals to digits and back |
| `VT100` | the terminal's escape sequences: cursor movement, colors |
| `GarbageCollectedHeap` | the collector: `Collect`, statistics, and finalizers |
| `Coroutines` | coroutines: `Init`, `Transfer`, `Free` (section 11) |

Each example below is in `doc/examples/runtime`.

**The arguments** (`Args`):

<!-- example: runtime/Echo.Mod -->
```
MODULE Echo;
  (* The program's arguments, from Args *)
  IMPORT Args, Out;
  VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
BEGIN
  FOR i := 1 TO Args.argc - 1 DO
    Args.Get(i, arg); Out.Int(i, 0); Out.String(": "); Out.String(arg); Out.Ln
  END
END Echo.
```

<!-- run: runtime -->
```
$ poc Echo.Mod
$ ./Echo one "two words"
1: one
2: two words
```

**Standard input** (`In`):

<!-- example: runtime/Sum.Mod -->
```
MODULE Sum;
  (* Integers from standard input, with In, until there are no more *)
  IMPORT In, Out;
  VAR n, total: INTEGER;
BEGIN
  total := 0;
  In.Open; In.Int(n);
  WHILE In.Done DO total := total + n; In.Int(n) END;
  Out.String("total "); Out.Int(total, 0); Out.Ln
END Sum.
```

<!-- run: runtime -->
```
$ poc Sum.Mod
$ echo 1 2 3 4 | ./Sum
total 10
```

**Standard output and standard error** (`Out`, `Err`):

<!-- example: runtime/Report.Mod -->
```
MODULE Report;
  (* Out writes to standard output, Err to standard error *)
  IMPORT Out, Err;
BEGIN
  Out.String("a result"); Out.Ln;
  Err.String("a warning"); Err.Ln
END Report.
```

<!-- run: runtime -->
```
$ poc Report.Mod
$ ./Report 2>/dev/null
a result
```

**Strings** (`Strings`):

<!-- example: runtime/Words.Mod -->
```
MODULE Words;
  IMPORT Strings, Out;
  VAR s: ARRAY 64 OF CHAR;
BEGIN
  s := "Peaseblossom";
  Strings.Append(" and Cobweb", s);
  Out.String(s); Out.String(", "); Out.Int(Strings.Length(s), 0); Out.String(" characters"); Out.Ln;
  Out.String("Cobweb is at "); Out.Int(Strings.Pos("Cobweb", s, 0), 0); Out.Ln;
  Strings.Cap(s); Out.String(s); Out.Ln
END Words.
```

<!-- run: runtime -->
```
$ poc Words.Mod
$ ./Words
Peaseblossom and Cobweb, 23 characters
Cobweb is at 17
PEASEBLOSSOM AND COBWEB
```

**Strings as input and output** (`InStr`, `OutStr`): each `InStr`
procedure reads from its position and moves it past what it read; each
`OutStr` procedure appends to its string what `Out` would write:

<!-- example: runtime/Fields.Mod -->
```
MODULE Fields;
  (* InStr reads a string as In reads standard input, moving pos on;
     OutStr appends to a string what Out would write *)
  IMPORT InStr, OutStr, Out;
  VAR pos: LONGINT; name: ARRAY 32 OF CHAR; count: INTEGER; price: REAL;
    line: ARRAY 80 OF CHAR;
BEGIN
  pos := 0;
  InStr.Name(name, "pears 12 0.75", pos);
  InStr.Int(count, "pears 12 0.75", pos);
  InStr.Real(price, "pears 12 0.75", pos);
  line := "";
  OutStr.String(name, line); OutStr.Int(count, 4, line);
  OutStr.Char(" ", line); OutStr.Real(count * price, 12, line);
  Out.String(line); Out.Ln
END Fields.
```

<!-- run: runtime -->
```
$ poc Fields.Mod
$ ./Fields
pears  12 9.000000E+00
```

**Mathematics** (`Math`):

<!-- example: runtime/Roots.Mod -->
```
MODULE Roots;
  (* REAL functions from Math (MathL has the same for LONGREAL) *)
  IMPORT Math, Out;
  VAR i: INTEGER;
BEGIN
  FOR i := 1 TO 4 DO
    Out.Int(i, 0); Out.String(" "); Out.Real(Math.sqrt(i), 0); Out.Ln
  END
END Roots.
```

<!-- run: runtime -->
```
$ poc Roots.Mod
$ ./Roots
1 1.0E+00
2 1.41421E+00
3 1.73205E+00
4 2.0E+00
```

**Files** (`Files`): a new file is anonymous until `Register` gives it its
name.

<!-- example: runtime/Notes.Mod -->
```
MODULE Notes;
  (* A file written, registered under its name, then read back *)
  IMPORT Files, Out;
  VAR f: Files.File; r: Files.Rider; line: ARRAY 80 OF CHAR;
BEGIN
  f := Files.New("notes.txt");
  Files.Set(r, f, 0);
  Files.WriteString(r, "first"); Files.WriteString(r, "second");
  Files.Register(f);
  f := Files.Old("notes.txt");
  Files.Set(r, f, 0);
  Files.ReadString(r, line);
  WHILE ~r.eof DO Out.String(line); Out.Ln; Files.ReadString(r, line) END;
  Files.Close(f)
END Notes.
```

<!-- run: runtime -->
```
$ poc Notes.Mod
$ ./Notes
first
second
```

**The environment** (`Platform`):

<!-- example: runtime/Env.Mod -->
```
MODULE Env;
  (* An environment variable, from Platform *)
  IMPORT Platform, Out;
  VAR value: ARRAY 256 OF CHAR;
BEGIN
  Platform.GetEnv("GREETING", value);
  IF value = "" THEN value := "(not set)" END;
  Out.String(value); Out.Ln
END Env.
```

<!-- run: runtime -->
```
$ poc Env.Mod
$ ./Env
(not set)
$ GREETING=hello ./Env
hello
```

**Signals** (`Platform`): `SetInterruptHandler` (and `SetQuitHandler`,
`SetBadInstructionHandler`) names a procedure to call when the program
gets the signal. It interrupts the program wherever it is, perhaps
halfway through `NEW` or a call of `Out`, so it may only set the
program's own variables: it must not use `NEW`, `Out`, `Err`, `In`,
`Files`, `Texts` or `Oberon`. Nothing detects a handler that does, and
what it breaks fails later, somewhere else. The main line reads what the
handler set by `SYSTEM.GET`, which reads memory every time; a loop such
as `WHILE ~interrupted DO .. END` may read the variable once, when
optimized, and never end.

<!-- example: runtime/Stop.Mod -->
```
MODULE Stop;
  (* Work until interrupted: the handler only sets a variable, which the
     main line reads by SYSTEM.GET *)
  IMPORT SYSTEM, Platform, Out;
  VAR interrupted, stop: BOOLEAN; rounds: LONGINT;

  PROCEDURE Interrupt(signal: SYSTEM.INT32);
  BEGIN interrupted := TRUE
  END Interrupt;

BEGIN
  Platform.SetInterruptHandler(Interrupt);
  REPEAT
    INC(rounds);
    SYSTEM.GET(SYSTEM.ADR(interrupted), stop)
  UNTIL stop;
  Out.String("interrupted"); Out.Ln
END Stop.
```

<!-- run: runtime -->
```
$ poc Stop.Mod
$ ./Stop & sleep 1; kill -INT $!; wait $!
interrupted
```

**Texts** (`Texts`, `Oberon`), for programs written for the Oberon system:

<!-- example: runtime/Log.Mod -->
```
MODULE Log;
  (* voc's Texts and Oberon: what is appended to Oberon.Log is written to
     standard output *)
  IMPORT Texts, Oberon;
  VAR w: Texts.Writer;
BEGIN
  Texts.OpenWriter(w);
  Texts.WriteString(w, "six times seven is "); Texts.WriteInt(w, 6 * 7, 0); Texts.WriteLn(w);
  Texts.Append(Oberon.Log, w.buf)
END Log.
```

<!-- run: runtime -->
```
$ poc Log.Mod
$ ./Log
six times seven is 42
```

**Finalizers** (`GarbageCollectedHeap`): a procedure that runs once an
object is no longer reachable, or when the program ends.

<!-- example: runtime/Finish.Mod -->
```
MODULE Finish;
  (* A finalizer runs once its object is unreachable, or at the end *)
  IMPORT SYSTEM, GarbageCollectedHeap, Out;
  TYPE Resource = POINTER TO RECORD name: ARRAY 16 OF CHAR END;
  VAR r: Resource;

  PROCEDURE Release(obj: SYSTEM.PTR);
    VAR done: Resource;
  BEGIN
    done := SYSTEM.VAL(Resource, obj);
    Out.String("released "); Out.String(done.name); Out.Ln
  END Release;

BEGIN
  NEW(r); r.name := "the file";
  GarbageCollectedHeap.RegisterFinalizer(r, Release);
  Out.String("working"); Out.Ln
END Finish.
```

<!-- run: runtime -->
```
$ poc Finish.Mod
$ ./Finish
working
released the file
```

## 11. Coroutines

A coroutine is a procedure running on a stack of its own, which can stop
in the middle of what it is doing, hand control to another coroutine, and
later carry on where it stopped. The module `Coroutines` has the
interface of Oakwood's optional module of that name, plus `Free` and
`DefaultStackSize`:

- `Init(body, stackSize, cor)` makes `cor` a new coroutine, which calls
  `body` the first time it is resumed. The stack has `stackSize` bytes,
  rounded up to whole pages; `Coroutines.DefaultStackSize` is a
  recommendation.
- `Transfer(from, to)` stores the running coroutine in `from` and resumes
  `to` where it last stopped. The main program is a coroutine too: the
  first `Transfer` out of it stores it in `from`, so that a `Transfer`
  back to that resumes it.
- `Free(cor)` gives back `cor`'s stack. A stack never freed is kept until
  the program ends.

Only `Transfer` switches: there are no threads underneath, so coroutines
share the program's variables without locks, and none can change them
while another is running. Each example below is in
`doc/examples/coroutines`.

**Two walks in step.** `WordSets` reads the words of two files into two
sorted trees, and says which words are only in the first (`<`), only in
the second (`>`), or in both (`=`). It must walk the two trees in order,
one word at a time from each, as a merge does. Each walk is the ordinary
recursive procedure, on its own coroutine, handing over one word and
transferring back to the main program; without coroutines each would have
to be rewritten with a stack of its own.

<!-- example: coroutines/WordSets.Mod -->
```
MODULE WordSets;  (* which words are in one file, the other, or both *)

  IMPORT Coroutines, Files, Args, Out;

  CONST maxWord = 64;

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      word: ARRAY maxWord OF CHAR;
      left, right: Node
    END;
    Walker = RECORD
      cor: Coroutines.Coroutine;
      tree: Node;
      current: Node   (* the word handed over; NIL after the last *)
    END;

  VAR
    main: Coroutines.Coroutine;
    a, b: Walker;
    name: ARRAY 256 OF CHAR;

  PROCEDURE Insert(VAR t: Node; VAR word: ARRAY OF CHAR);
  BEGIN
    IF t = NIL THEN NEW(t); COPY(word, t.word)
    ELSIF word < t.word THEN Insert(t.left, word)
    ELSIF word > t.word THEN Insert(t.right, word)
    END
  END Insert;

  PROCEDURE IsWordChar(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (CAP(ch) >= "A") & (CAP(ch) <= "Z") OR (ch >= "0") & (ch <= "9")
  END IsWordChar;

  PROCEDURE ReadWords(name: ARRAY OF CHAR; VAR tree: Node);
    VAR f: Files.File; r: Files.Rider; ch: CHAR;
      word: ARRAY maxWord OF CHAR; i: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN
      Out.String("cannot open "); Out.String(name); Out.Ln; HALT(1)
    END;
    Files.Set(r, f, 0); Files.Read(r, ch);
    WHILE ~r.eof DO
      IF IsWordChar(ch) THEN
        i := 0;
        REPEAT
          IF i < maxWord - 1 THEN word[i] := ch; INC(i) END;
          Files.Read(r, ch)
        UNTIL r.eof OR ~IsWordChar(ch);
        word[i] := 0X; Insert(tree, word)
      ELSE Files.Read(r, ch)
      END
    END
  END ReadWords;

  PROCEDURE Height(t: Node): LONGINT;
    VAR l, r: LONGINT;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    l := Height(t.left); r := Height(t.right);
    IF l > r THEN RETURN l + 1 ELSE RETURN r + 1 END
  END Height;

  (* The walk: ordinary in-order recursion, handing each node to main. *)
  PROCEDURE Walk(t: Node; VAR w: Walker);
  BEGIN
    IF t # NIL THEN
      Walk(t.left, w);
      w.current := t; Coroutines.Transfer(w.cor, main);
      Walk(t.right, w)
    END
  END Walk;

  (* A body must not return: after the last word, hand over NIL forever. *)
  PROCEDURE Finish(VAR w: Walker);
  BEGIN
    w.current := NIL;
    LOOP Coroutines.Transfer(w.cor, main) END
  END Finish;

  PROCEDURE WalkA; BEGIN Walk(a.tree, a); Finish(a) END WalkA;
  PROCEDURE WalkB; BEGIN Walk(b.tree, b); Finish(b) END WalkB;

  PROCEDURE Next(VAR w: Walker);
  BEGIN Coroutines.Transfer(main, w.cor)
  END Next;

  PROCEDURE Show(mark: CHAR; n: Node);
  BEGIN Out.Char(mark); Out.Char(" "); Out.String(n.word); Out.Ln
  END Show;

BEGIN
  IF Args.argc # 3 THEN
    Out.String("usage: wordsets file1 file2"); Out.Ln; HALT(2)
  END;
  Args.Get(1, name); ReadWords(name, a.tree);
  Args.Get(2, name); ReadWords(name, b.tree);
  (* A walk is as deep as its tree is high; sorted input makes a list. *)
  Coroutines.Init(WalkA, 16384 + 256 * Height(a.tree), a.cor);
  Coroutines.Init(WalkB, 16384 + 256 * Height(b.tree), b.cor);
  Next(a); Next(b);
  WHILE (a.current # NIL) OR (b.current # NIL) DO
    IF (b.current = NIL) OR (a.current # NIL) & (a.current.word < b.current.word) THEN
      Show("<", a.current); Next(a)
    ELSIF (a.current = NIL) OR (b.current.word < a.current.word) THEN
      Show(">", b.current); Next(b)
    ELSE
      Show("=", a.current); Next(a); Next(b)
    END
  END
END WordSets.
```

With a memo and a list of words:

<!-- example: coroutines/memo.txt -->
```
The meeting moved to Thursday. Bring the
budget, the schedule and the new plans.
```

<!-- example: coroutines/words.txt -->
```
and bring budget meeting moved new plan plans
schedule the thursday to tuesday
```

<!-- run: coroutines -->
```
$ poc WordSets.Mod
$ ./WordSets memo.txt words.txt
< Bring
< The
< Thursday
= and
> bring
= budget
= meeting
= moved
= new
> plan
= plans
= schedule
= the
> thursday
= to
> tuesday
```

Words are compared as they are spelt, capitals included, so `Bring` at
the start of a sentence is not `bring`. The `<` lines are what a spelling
checker would report.

**A search that hands over its results.** `Queens` places `k` queens on an
`n`×`n` board, no two attacking each other, with Wirth's backtracking
search. Each time the search finds a solution it transfers to the main
program, which shows it and decides whether to ask for another. The
search stays the textbook's recursive procedure, and the main program
stays in control: it can stop after any solution, or wait for the user
between two of them, without the search knowing why.

<!-- example: coroutines/Queens.Mod -->
```
MODULE Queens;  (* k queens on an n x n board, one solution at a time *)

  IMPORT Coroutines, Args, In, Out;

  CONST
    maxSize = 26;   (* files a to z *)
    (* modes *)
    askEachTime = 0; firstCount = 1; everySolution = 2;

  VAR
    main, solver: Coroutines.Coroutine;
    n, k: INTEGER;   (* the board's size and the number of queens *)
    column: ARRAY maxSize OF INTEGER;   (* row r's queen's column, -1 if none *)
    columnTaken: ARRAY maxSize OF BOOLEAN;
    upTaken, downTaken: ARRAY 2 * maxSize - 1 OF BOOLEAN;   (* the diagonals *)
    found: BOOLEAN;   (* TRUE: column holds a solution; FALSE: no more *)
    mode: INTEGER;
    count, limit: LONGINT;
    going: BOOLEAN;
    answer: ARRAY 80 OF CHAR;

  (* Wirth's backtracking search, with two changes: a row may be left
     empty while enough rows remain for the queens still to place, and
     each solution is handed to main instead of printed. A row not yet
     given a queen has column -1, and every path puts that back. *)
  PROCEDURE Place(row, placed: INTEGER);
    VAR c: INTEGER;
  BEGIN
    IF placed = k THEN
      found := TRUE; Coroutines.Transfer(solver, main)
    ELSIF n - row >= k - placed THEN
      FOR c := 0 TO n - 1 DO
        IF ~columnTaken[c] & ~upTaken[row + c] & ~downTaken[row - c + n - 1] THEN
          column[row] := c;
          columnTaken[c] := TRUE; upTaken[row + c] := TRUE;
          downTaken[row - c + n - 1] := TRUE;
          Place(row + 1, placed + 1);
          columnTaken[c] := FALSE; upTaken[row + c] := FALSE;
          downTaken[row - c + n - 1] := FALSE;
          column[row] := -1
        END
      END;
      Place(row + 1, placed)   (* and with this row empty *)
    END
  END Place;

  (* The solver's body. It must not return: after the last solution it
     answers every Transfer with "no more". *)
  PROCEDURE Solve;
    VAR r: INTEGER;
  BEGIN
    FOR r := 0 TO n - 1 DO column[r] := -1 END;
    Place(0, 0);
    found := FALSE;
    LOOP Coroutines.Transfer(solver, main) END
  END Solve;

  PROCEDURE NextSolution(): BOOLEAN;
  BEGIN
    Coroutines.Transfer(main, solver);
    RETURN found
  END NextSolution;

  PROCEDURE Rule;
    VAR c: INTEGER;
  BEGIN
    Out.Char("+");
    FOR c := 0 TO n - 1 DO Out.String("---+") END;
    Out.Ln
  END Rule;

  (* The solution's number, its queens' squares in chess notation, and
     the board, the last rank at the top. *)
  PROCEDURE Show(number: LONGINT);
    VAR r, c: INTEGER;
  BEGIN
    Out.String("Solution "); Out.Int(number, 0); Out.Char(":");
    FOR r := 0 TO n - 1 DO
      IF column[r] >= 0 THEN
        Out.Char(" "); Out.Char(CHR(ORD("a") + column[r])); Out.Int(r + 1, 0)
      END
    END;
    Out.Ln;
    FOR r := n - 1 TO 0 BY -1 DO
      Rule; Out.Char("|");
      FOR c := 0 TO n - 1 DO
        IF column[r] = c THEN Out.String(" Q |") ELSE Out.String("   |") END
      END;
      Out.Ln
    END;
    Rule
  END Show;

  PROCEDURE Usage;
  BEGIN
    Out.String("usage: queens [-n size] [-k queens] [all | count]"); Out.Ln;
    Out.String("size 1 to 26, 8 if not given; queens 1 to size, size if not given");
    Out.Ln;
    HALT(2)
  END Usage;

  PROCEDURE Upper(ch: CHAR): CHAR;
  BEGIN
    IF (ch >= "a") & (ch <= "z") THEN ch := CAP(ch) END;
    RETURN ch
  END Upper;

  (* Whether s is word, in either case: DCL passes an argument not in
     quotes in capitals. *)
  PROCEDURE Is(s, word: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (word[i] # 0X) & (Upper(s[i]) = Upper(word[i])) DO INC(i) END;
    RETURN (word[i] = 0X) & (s[i] = 0X)
  END Is;

  (* Argument i as a number from low to high, or the usage message *)
  PROCEDURE Number(i: INTEGER; low, high: LONGINT): LONGINT;
    VAR value: LONGINT;
  BEGIN
    value := low - 1; Args.GetInt(i, value);
    IF (value < low) OR (value > high) THEN Usage END;
    RETURN value
  END Number;

  PROCEDURE ReadArguments;
    VAR i: INTEGER; arg: ARRAY 32 OF CHAR;
  BEGIN
    n := 8; k := 0; mode := askEachTime;
    i := 1;
    WHILE i < Args.argc DO
      Args.Get(i, arg);
      IF Is(arg, "-n") & (i + 1 < Args.argc) THEN
        INC(i); n := SHORT(Number(i, 1, maxSize))
      ELSIF Is(arg, "-k") & (i + 1 < Args.argc) THEN
        INC(i); k := SHORT(Number(i, 1, maxSize))
      ELSIF mode # askEachTime THEN Usage
      ELSIF Is(arg, "all") THEN mode := everySolution
      ELSE mode := firstCount; limit := Number(i, 1, MAX(LONGINT))
      END;
      INC(i)
    END;
    IF k = 0 THEN k := n ELSIF k > n THEN Usage END
  END ReadArguments;

BEGIN
  ReadArguments;
  IF mode = askEachTime THEN In.Open END;
  Out.Int(k, 0); Out.String(" queen");
  IF k > 1 THEN Out.Char("s") END;
  Out.String(" on a "); Out.Int(n, 0); Out.Char("x");
  Out.Int(n, 0); Out.String(" board"); Out.Ln;
  (* The search is at most n + 1 calls of Place deep, below Solve: a
     small stack is plenty. *)
  Coroutines.Init(Solve, 16384, solver);
  count := 0; going := TRUE;
  WHILE going & NextSolution() DO
    INC(count); Show(count);
    CASE mode OF
    | askEachTime:
        Out.String("Another? [Y/n] "); Out.Flush;
        In.Line(answer);
        going := In.Done & (Upper(answer[0]) # "N")
    | firstCount:
        going := count < limit
    | everySolution:
    END
  END;
  IF going THEN
    Out.String("No more: "); Out.Int(count, 0); Out.String(" solutions in all.");
    Out.Ln
  END
END Queens.
```

`queens [-n size] [-k queens] [all | count]`: with no count, it asks after
each solution whether to go on (Return or `y` goes on; `n`, or the end of
the input, stops). A count prints that many solutions, `all` every one:

<!-- run: coroutines -->
```
$ poc Queens.Mod
$ ./Queens -n 5 -k 3 2
3 queens on a 5x5 board
Solution 1: a1 c2 e3
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   |   |   |   | Q |
+---+---+---+---+---+
|   |   | Q |   |   |
+---+---+---+---+---+
| Q |   |   |   |   |
+---+---+---+---+---+
Solution 2: a1 c2 b4
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   | Q |   |   |   |
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   |   | Q |   |   |
+---+---+---+---+---+
| Q |   |   |   |   |
+---+---+---+---+---+
$ ./Queens -n 4 all
4 queens on a 4x4 board
Solution 1: b1 d2 a3 c4
+---+---+---+---+
|   |   | Q |   |
+---+---+---+---+
| Q |   |   |   |
+---+---+---+---+
|   |   |   | Q |
+---+---+---+---+
|   | Q |   |   |
+---+---+---+---+
Solution 2: c1 a2 d3 b4
+---+---+---+---+
|   | Q |   |   |
+---+---+---+---+
|   |   |   | Q |
+---+---+---+---+
| Q |   |   |   |
+---+---+---+---+
|   |   | Q |   |
+---+---+---+---+
No more: 2 solutions in all.
$ ./Queens all | tail -n 1
No more: 92 solutions in all.
```

Both programs run unchanged on VAX/VMS, as foreign commands
(`QUEENS :== $DEV:[DIR]QUEENS.EXE`, then `QUEENS -N 4 ALL`).

**The rules.** `Coroutines` checks what is cheap to check, and the rest
is the program's to keep:

- **A body never returns.** It ends by transferring away for good, as
  `Finish` and `Solve` do above. One that returns traps (status 16).
- **Misuse traps** (status 17), with a message that says which: a
  `Transfer` to a coroutine never given to `Init`, or to one freed; a
  `Free` of the running coroutine or of the main program's; a `Transfer`
  in a finalizer, or in a `Platform` signal handler (on VAX/VMS, at AST
  level).
- **No memory for a stack** traps (status 18), always: unlike `NEW`,
  `Init` has no NIL to leave.
- **A stack does not grow.** It is fixed at `Init`, with an inaccessible
  page below it, and running past its end ends the program with
  `SIGSEGV` (on VAX/VMS, an access violation). Only the pages a coroutine
  touches cost memory on Unix, so `DefaultStackSize` is 256 KiB there and
  the least is 16 KiB; on VAX/VMS the whole stack counts against the
  page-file quota, and they are 32 KiB and 8 KiB. A deep recursion needs
  a stack sized for it: `WordSets` sizes each from its tree's height.
- **A blocking call stops every coroutine.** Reading input waits for the
  whole program, which is what `Queens` wants while it waits for the
  user.
- **A coroutine may switch out of a C callback**, but must be resumed,
  and must return to C, before anything else uses that library. No C++
  exception or `longjmp` may cross a switch.
- **The program has one thread.** It must not start another, from C
  either.

The collector finds the pointers on every coroutine's stack, suspended or
running.

A debugger sees only the running coroutine. gdb's backtrace in a
coroutine lists its procedures down to its body and ends at
`Coroutines.-start`; a suspended coroutine has no thread to switch to, so
its frames can be seen only once it is resumed. On VAX/VMS a traceback,
or the debugger's `SHOW CALLS`, ends at `POC_COROUTINE_START` in the same
way.

## 12. Coming from voc

poc reads what voc reads, with the same two size models, and a program
written for voc usually builds unchanged. What differs:

- **The command line.** `poc <file>` builds one program, compiling every
  module it imports; there are no per-file options, and an option does not
  toggle when it is repeated. voc's `-m` is poc's default, `-M` is
  `-static`, `-S` is `-emit-llvm-ir`, `-c` is `-compile`, `-r` is
  `-range-checks` and `-V` is `-verbose`. voc's `CFLAGS`, `LDFLAGS` and
  `LDLIBS` are `-c-flag` and `-link`. `voc -e`, `-s` and `-F` have no
  counterpart: poc writes every `.sym` again from the source.
- **The checks are always on.** voc's `-a`, `-t`, `-x` and `-p` are on by
  default and can be turned off; poc's cannot. poc checks two things voc
  checks only with `-t` or not at all: a function procedure that reaches its
  `END` (status 12) and a record assigned to a variable whose dynamic type
  extends its static type (status 13).
- **Traps** say what happened in words and exit with poc's own statuses
  (section 7), where voc prints "Terminated by Halt(n)". `HALT(n)` takes
  `n` from 0 to 255 and says nothing.
- **`SET`** has 32 bits under `-OC` too; `SYSTEM.SET64` has 64.
- **Read-only parameters** (`PROCEDURE P(x-: T)`) take any argument, a
  constant or a string included, where voc's take only a variable, and a
  small one is passed by value (Reference Guide, "Read-only parameters").
- **voc's library modules** (those of its `src/library`: `ethMD5`, the ooc
  and Oakwood modules and the rest) are not in poc yet; the runtime modules
  of section 10 are.
- **Variables start at zero**, locals included: every pointer starts NIL,
  as with voc's `-p`, and every number at 0.
- **A `FOR` loop ends before a step past its final value**: after it, the
  control variable holds the last value it had in the body, where voc's
  has one step more, and a loop up to `MAX` of its type ends (Reference
  Guide, section 3, "Not extensions, though the report differs").

poc also takes some of voc's extensions, among them `HUGEINT`,
`SYSTEM.INT8` to `SYSTEM.INT64`, `ASSERT`, and hexadecimal constants of 16
digits as 64-bit patterns, and has some of its own, among them the unsigned
integer types `SHORTCARD` to `HUGECARD`, `SYSTEM.CARD8` to `SYSTEM.CARD64`
and `SYSTEM.CARD`, with `VAL` to cross to the signed ones, which
voc does not have (Reference Guide, "Unsigned integer types"). `-strict`
rejects them all.

## 13. poc on VAX/VMS

poc also compiles for VAX/VMS 5.5-2, writing VAX MACRO-32 that VMS's own
assembler and linker make into an image. It does so on Unix as a
cross-compiler, `poc -target vax-dec-vms`, or on VMS itself, where poc
runs too, built from a kit in the release. The *Peaseblossom VAX/VMS
Guide* (`doc/vax-vms-guide.md` in the source tree) covers that target:
installing the kits, building programs and libraries, how VAX/VMS
differs from the Unix targets, the runtime modules there, and calling
VMS's own system services and libraries from Oberon.
