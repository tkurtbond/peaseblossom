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
11. Coming from voc

## 1. Installing

poc needs `clang` on `PATH` when it builds a program: it writes LLVM IR, and
clang compiles and links it. Any clang from 19 on does; on the BSDs it is
the system's (OpenBSD and FreeBSD) or pkgsrc's (NetBSD). Building poc needs
GNU make, which the BSDs call `gmake`.

**From a release tarball.** A release, `peaseblossom-<version>.tar.gz`,
carries poc's own LLVM IR, its *seed*, so clang alone can build it:

    tar xzf peaseblossom-0.1.0.tar.gz
    cd peaseblossom-0.1.0
    make                       # gmake on the BSDs
    make install               # as root, or with PREFIX=$HOME/local
    make check-install         # optional: builds programs with what was installed

`make install` takes `PREFIX` (default `/usr/local`) and `DESTDIR`, and the
usual `BINDIR`, `LIBDIR`, `MANDIR` and `DOCDIR`. It installs:

| Where | What |
|---|---|
| `$(BINDIR)/poc` | the compiler |
| `$(LIBDIR)/poc/<triple>/O2/`, `OC/` | the runtime, the library `poc-rtl`, for each size model (section 3) |
| `$(LIBDIR)/poc/<triple>/O2-g/`, `OC-g/` | the same, built with debug information, which `poc -g` uses (section 8) |
| `$(DOCDIR)` | `README.md`, `LICENSE` and this guide, `users-guide.md` |

poc finds its runtime as `../lib/poc` from the directory it is in, following
symbolic links, so `LIBDIR` must be `$(BINDIR)/../lib` (the default), and a
link to poc from anywhere works. `make uninstall` removes what `make install`
wrote, and leaves any other library installed beside the runtime.

**From git.** A checkout has no seed. poc is built by voc (Vishap Oberon, the
compiler poc was first written with), if `VOC_BIN_DIR` names its `bin`
directory, or by a poc already installed:

    make BOOTSTRAP_POC=/usr/local/bin/poc

`make check` runs the test suite; it needs voc, which it compares poc with.

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

Every build compiles every module of the program from its source again: poc
keeps no record of what changed. A module that should not be compiled again
belongs in a library (section 5).

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
bits and `SET` 32 under both. A program and every module it uses are
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
  (section 9): `-link -lz`, `-link -L/opt/lib`. Repeatable.
- `-verbose`: prints each command poc runs.
- `-target <triple>`: builds for another target than the host's, as far as
  clang can (it needs that target's C library to link).
- `-range-checks`, `-trap-location`, `-trap-heap-exhausted`: section 7. `-g`:
  section 8.

Options come before the file.

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
| 14 | with `-range-checks`: `SHORT` or `CHR` of a value that does not fit |

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

**A module's part in C.** A file `<Module>.c` beside `<Module>.Mod` is
compiled with the module and linked wherever the module is, into a program
or a library: the module's own C, which its `["C"]` procedures call.
`-c-flag <arg>` passes `<arg>` to clang when it compiles it (`-c-flag
-I/opt/include`).

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

Each example below is in `doc/examples/runtime`.

**The arguments** (`Modules`):

<!-- example: runtime/Echo.Mod -->
```
MODULE Echo;
  (* The program's arguments, from Modules *)
  IMPORT Modules, Out;
  VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
BEGIN
  FOR i := 1 TO Modules.ArgCount - 1 DO
    Modules.GetArg(i, arg); Out.Int(i, 0); Out.String(": "); Out.String(arg); Out.Ln
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

## 11. Coming from voc

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
- **Read-only parameters** (`PROCEDURE P(x-: T)`) are not in poc.
- **voc's library modules** (those of its `src/library`: `ethMD5`, the ooc
  and Oakwood modules and the rest) are not in poc yet; the runtime modules
  of section 10 are.
- **Variables start at zero**, locals included: every pointer starts NIL,
  as with voc's `-p`, and every number at 0.

poc also takes some of voc's extensions, among them `HUGEINT`,
`SYSTEM.INT8` to `SYSTEM.INT64`, `ASSERT`, and hexadecimal constants of 16
digits as 64-bit patterns. `-strict` rejects them all.
