# The Peaseblossom VAX/VMS Guide

poc, the Peaseblossom Oberon Compiler, compiles Oberon-2 for **VAX/VMS
5.5-2** as well as for the Unix systems the *User's Guide* describes. For
the VAX it writes VAX MACRO-32, which VMS's own assembler, MACRO,
assembles, and LINK links the objects into an image. It needs nothing
beyond the VMS base system: no compiler or other layered product, and no
privilege.

poc can be used two ways, and this guide covers both:

- **On VMS itself.** poc runs there too, as `POC.EXE`, built from the
  MACRO-32 in its kit. It compiles, then writes a DCL procedure that
  assembles and links the program.
- **As a cross-compiler on Unix**, `poc -target vax-dec-vms`. It writes the
  MACRO-32 and the DCL procedure there, and you copy them to VMS to
  assemble, link and run.

The language is the one the *User's Guide* describes, with the same
extensions. What differs is what a VAX and VMS make different: real
numbers, file names, how a program reports a failure, and how it reaches
the system (chapter 5).

The guide has two kinds of reader, and each chapter says which it is
for:

- someone who knows Oberon and poc on Unix and wants to write VMS programs.
  They need what differs, and how VMS's own facilities are reached.
- someone who knows VMS and wants to write Oberon there. They need the
  kits, the commands, and how VMS's conventions (condition values,
  descriptors, logical names) look from Oberon.

Every program in this guide is a file under `doc/examples/vax`.

## Contents

1. Installing
2. A first program
3. Building programs
4. Libraries
5. How VAX/VMS differs from the Unix targets
6. The runtime modules on VMS
7. Calling VMS
8. VMSLIB
9. The supported routines in VMSDEF
10. Commands with qualifiers
11. Records RMS keeps
12. Screens
13. Conditions and handlers
14. Asynchronous system traps
15. Subprocesses
16. When a program fails on VMS
17. poc on VMS itself

Appendices: A. The kits' contents. B. What is left out, and why.
C. Further reading.

## 1. Installing

*For both kinds of reader.*

### On VMS

A release carries poc for VMS as two text files, with the version's
periods made hyphens (`POC-0-7-0.COM` for 0.7.0):

- `POC-<version>.COM`, the **base kit**: poc, and its runtime library
  `POCRTL`.
- `POC-VMS-<version>.COM`, the **STARLET kit**: VMS's own interfaces as
  two more libraries. `VMSDEF` holds the system services, the run-time
  library routines and STARLET's definitions, generated from
  `SYS$LIBRARY:STARLETSD.TLB`. `VMSLIB` holds twelve modules built on
  them (chapter 8). A program that calls nothing of VMS's own needs only
  the base kit.

Each kit is a DCL procedure that unpacks itself into the directory it is
run in, and everything in it is text.

1. **Copy the kits to VMS in ASCII mode**: with FTP, `ascii` before `put`.
   VMS keeps a file copied in binary mode as fixed 512-byte records, and
   such a kit will not run.
2. **Make an empty directory for poc and unpack the base kit there.** The
   directory may be at most four names deep, since the kit adds four more
   below it, and VMS allows eight. Unpack the STARLET kit too, now or
   later:

       $ CREATE/DIRECTORY [.POC]
       $ SET DEFAULT [.POC]
       $ @[-]POC-0-7-0
       $ @[-]POC-VMS-0-7-0

   The base kit makes `[.BIN]`, `[.KIT]` (poc's own MACRO-32),
   `[.LIB.POC.VAX-DEC-VMS.O2]` and `[.OC]` (the libraries), `[.SRC]` (the
   source poc for VMS is built from), `BUILD.COM`, `SETUP.COM`,
   `README.TXT`, `LICENSE.TXT` and `VERSION.TXT`. The STARLET kit adds its
   two libraries with their sources, and `README-VMS.TXT`. It refuses to
   unpack anywhere but in a poc of its own version.
3. **Build:**

       $ @BUILD

   This assembles and links `POC.EXE` into `[.BIN]`, then builds every
   library that is there, under both size models (chapter 3). It takes a
   while; `BUILD.LOG` has each step's time. `@BUILD` builds only what is
   not built yet, so after the STARLET kit is unpacked into a built
   installation, `@BUILD` builds just `VMSDEF` and `VMSLIB`. To build
   something again, delete it first (`POC.EXE`, or a library's `.OLB`).
   `@BUILD O2` or `@BUILD OC` builds one size model's libraries, and
   `@BUILD BOTH CLEAN` deletes `[.KIT]` once `POC.EXE` is built.
4. **Set up each process that uses poc**, once a session or from
   `LOGIN.COM`:

       $ @dev:[dir.POC]SETUP

   `SETUP.COM` defines the command `POC` and the logical names of the
   `-O2` libraries that are built. `@SETUP OC` defines the `-OC` ones
   instead: a process builds against one size model's libraries at a
   time.

Check the installation with `POC -VERSION`:

    $ POC -VERSION
    poc 0.7.0
    target vax-dec-vms, size model -O2

### On Unix

poc for Unix has the VAX back end built in: `poc -target vax-dec-vms`
needs nothing more than an installed poc (the *User's Guide*, chapter 1).
What it needs besides is the VAX runtime, the modules of `rtl/vax` in
poc's source tree, as source or made into the library `POCRTL` (chapter
3). The STARLET kit's modules are `rtl/vax/vms` and `rtl/vax/vmslib`.

<!-- TODO with the packaging work, after vax is merged: the
peaseblossom-vax package and make install-vax, and where they put
POCRTL, VMSDEF and VMSLIB, so that -target vax-dec-vms finds them as
poc-rtl is found. -->

## 2. A first program

*For both kinds of reader.*

<!-- example: vax/hello/Hello.Mod -->
```
MODULE Hello;
  IMPORT Out;
BEGIN
  Out.String("Hello, world"); Out.Ln
END Hello.
```

### On VMS

<!-- vax-session: hello -->

    $ POC HELLO.MOD
    $ @HELLO
    $ RUN HELLO
    Hello, world

`POC` compiles `HELLO.MOD`, and every module it imports that does not
come from a library, to MACRO-32, one `.MAR` file each, and writes
`HELLO.COM`. Like poc on Unix it says nothing when it succeeds. `@HELLO`
assembles the program's modules and links `HELLO.EXE` against `POCRTL`.
`RUN HELLO` runs it.

DCL turns what you type into capitals, unless it is quoted, so poc on VMS
takes its options in any case: `POC -O HI HELLO.MOD` writes `HI.COM`,
which links `HI.EXE`.

### On Unix, then VMS

Cross-compiling writes the same files on Unix. The runtime's modules come
from `rtl/vax` in poc's source tree, here given as the import path:

    $ poc -target vax-dec-vms -import-path ~/src/peaseblossom/rtl/vax -build Hello.Mod

This writes `Hello.mar`, the `.mar` of each runtime module the program
uses (`Out`, `FormattedOutput`, `FormattedText`, `RealDigits` and
`LineOutput`), their `.sym` files, and `Hello.com`. Copy the `.mar` files
and `Hello.com` to VMS in ASCII mode, with the runtime's own MACRO-32,
`rtl/vax/PocRtl.mar`. Then, on VMS:

    $ MACRO/OBJECT POCRTL.MAR
    $ @HELLO
    $ RUN HELLO
    Hello, world

A program compiled from the runtime's source links its modules as
objects, with `POCRTL.OBJ`. `HELLO.COM` takes that from the current
directory, or from `POC$RTL:` when that logical name is defined, so it
need be assembled only once.

A program built on Unix against the library `POCRTL` (chapter 4) needs
only its own `.mar` files and its `.com` file on VMS, where `@SETUP` has
defined `POCRTL`'s logical names. The kit must then be the same version
of poc as the one on Unix: `HELLO.COM` checks that the library was set
up, and LINK checks that its interface is the one the program was
compiled against.

## 3. Building programs

*For both kinds of reader.*

### What a build writes

poc compiles the program's main module and every module it imports that
does not come from a library. It writes `<Module>.sym`, the module's
interface, and `<Module>.mar`, its MACRO-32, in the current directory or
in the directory `-output-dir` names. Then it writes a DCL procedure,
`<Main>.com`, or `-o`'s path with `.com`, which:

1. checks, for each library the program uses, that the library's setup
   procedure has defined its logical names. If one has not, it stops
   before doing anything, with a message naming the library:

       program HELLO needs library POCRTL: run its POCRTL_SETUP.COM first

2. assembles each module, `MACRO/OBJECT`, imports first;
3. writes a linker options file, `<IMAGE>.OPT`, listing the objects (the
   main module's first) and each library;
4. links `<IMAGE>.EXE`.

A warning stops the procedure: it starts with `ON WARNING THEN EXIT
$STATUS`, so a MACRO warning or `%LINK-W-MULDEF` ends it with that step's
status. Otherwise it exits with LINK's. The procedure is run where the
`.mar` files are. `-o`'s last part, without `.exe`, must be a name VMS
takes: 1 to 39 letters, digits, `_`, `$` and `-`.

`-compile <file>...` writes the named modules' `.mar` files and a
procedure that only assembles them, with no program's start.

### Size models

As on Unix, `-O2` (the default) gives `SHORTINT`, `INTEGER` and `LONGINT`
8, 16 and 32 bits, and `-OC` gives them 16, 32 and 64. `HUGEINT` is a
quadword under both. A program and every library it uses must be
compiled under one model. The kit builds each library under both, in
`[.LIB.POC.VAX-DEC-VMS.O2]` and `[.OC]`. A process sets up one model's
libraries at a time (`@SETUP` or `@SETUP OC`), so to build under the
other, run `@SETUP` again with it.

    $ POC -OC SIZES.MOD

### Object libraries or shareable images

Every library is built both as an object library, `<NAME>.OLB`, and as a
shareable image, `<NAME>.EXE`. By default a program links each library's
object library, and the image holds the code it uses: it runs on its own.
With `-shared-libraries` a program links the shareable images instead. Its
image is much smaller, and finds each library's image at run time by the
logical name `<NAME>`, which the library's setup procedure defines.

    $ POC -SHARED-LIBRARIES HELLO.MOD

Such a program runs only where the libraries' images are, set up, and
built from the same interface (chapter 4 shows what happens otherwise).

### Where poc finds modules

A module named in an `IMPORT` is found as on Unix (the *User's Guide*,
chapter 4): in a library on the library path, compiled already; else as
source, in the current directory and then in each directory of the import
path; else as a `.sym` with its `.mar`. On VMS:

- the import path is `-import-path <dir>`, repeatable, then the search
  list `POC$IMPORT`, where Unix has `POC_IMPORT_PATH`;
- the library path is `-library-path <dir>`, repeatable, then the search
  list `POC$LIBRARY`, where Unix has `POC_LIBRARY_PATH`, then
  `[.LIB.POC]` beside poc's own `[.BIN]`, where the kit's libraries are.

A search list is a logical name with several translations, tried in
order:

    $ DEFINE POC$IMPORT DISK$USER:[ME.MODULES], DISK$USER:[ME.SHARED]

### Long command lines and wildcards

DCL limits how long a command may be. An argument `@<file>` stands for
the arguments in `<file>`, one a line. poc expands a file name's
wildcards, `*` and `%`, itself, since DCL does not.

    $ POC -LIBRARY SHAPES *.MOD

### What poc on VMS does not have

poc on VMS has no LLVM back end. It compiles for VAX/VMS only, and refuses
the options that only the LLVM back end has: `-lto`, `-g`, `-opt`,
`-static`, `-link`, `-c-flag`, `-rebuild`, `-verbose`, `-emit-llvm-ir` and
`-dump-llvm-types`. On Unix, `-target vax-dec-vms` refuses them too.

## 4. Libraries

*For both kinds of reader.*

A library is a set of modules compiled once, which programs then use
without compiling them again (the *User's Guide*, chapter 5). On VMS a
library is also an object library and a shareable image, which its own
DCL procedures build.

### Making one

    $ POC -LIBRARY SHAPES SHAPEBASE.MOD SHAPES.MOD

`-library <name> <file>...` compiles the modules from source into the
library's directory, `[<output-dir>.VAX-DEC-VMS.<O2|OC>]` (by default
under the current directory). There it writes each module's `.sym` and
`.mar`, the library's manifest, and two procedures:

- `<NAME>_SETUP.COM` defines the library's logical names:
  `POC$LIB_<NAME>`, its directory, and `<NAME>`, its shareable image. Run
  it in each process that builds or runs a program against the library.
- `<NAME>_BUILD.COM` assembles the modules, makes `<NAME>.OLB` with
  LIBRARY, and links `<NAME>.EXE` shareable, every global symbol of the
  library made universal. First it checks that each library this one
  needs has been set up.

Every library needs `POCRTL`, since its code calls the runtime. A library
whose modules import another library's needs that one too, and its
procedure links against it.

    $ @[.VAX-DEC-VMS.O2]SHAPES_SETUP
    $ @[.VAX-DEC-VMS.O2]SHAPES_BUILD

A `.mar` file named among the modules is a part of the library, assembled
with them: `POCRTL` is made from `rtl/vax`'s modules and `PocRtl.mar`.

On Unix, `poc -target vax-dec-vms -library` writes the same files.
Copy the whole directory to VMS and run the two procedures there.

### Installing one

    $ POC -INSTALL-LIBRARY SHAPES -OUTPUT-DIR DISK$USER:[ME.LIB]

`-install-library <name>` copies what the library path has of the
library into `[<output-dir>.VAX-DEC-VMS.<O2|OC>]`, as text: the `.sym`,
`.mar` and manifest, and the two procedures. Run its build procedure
there, which makes the `.OLB` and `.EXE` in place and whose setup
procedure then names that directory. An installation in the directory a
copy is in already, or that would hold a module of another library, is
refused.

### When a library and a program do not match

A program linked against shareable images finds them only at run time,
and VMS checks there that each is the one it was linked against. These
are the messages a library's user meets.

The library's image is not found, because its setup procedure has not
been run:

    %DCL-W-ACTIMAGE, error activating image SHAPES
    -CLI-E-IMAGEFNF, image file not found DUA0:[SYS0.SYSCOMMON.][SYSLIB]SHAPES.EXE;

The library's image was linked again after the program was:

    %DCL-W-ACTIMAGE, error activating image SHAPES
    -CLI-E-IMGNAME, image file DISK$USER:[ME.LIB.VAX-DEC-VMS.O2]SHAPES.EXE;2
    -SYSTEM-F-SHRIDMISMAT, ident mismatch with shareable image

Link the program again. And a program compiled against another interface
of one of the library's modules than the library has now does not link:

    %LINK-W-NUDFSYMS, 1 undefined symbol:
    %LINK-I-UDFSYM,     POC_K1_A3C80D9A07A0DA0C

Each module defines a symbol `POC_K1_<key>`, the key a hash of its
interface, and each module that imports it refers to that symbol. So a
link fails, rather than an image going wrong, when the two disagree.
Compile the program again against the library as it is.

## 5. How VAX/VMS differs from the Unix targets

*For the Unix reader: everything here differs from what the User's
Guide says, and nothing else does.*

### Reals

A VAX has its own real formats, not IEEE 754's. `REAL` is F_floating and
`LONGREAL` G_floating:

| Type | Format | Size | Precision | Range of magnitudes |
|---|---|---|---|---|
| `REAL` | F_floating | 4 bytes | 24 bits | about 0.29 * 10^-38 to 1.7 * 10^38 |
| `LONGREAL` | G_floating | 8 bytes | 53 bits | about 0.56 * 10^-308 to 0.9 * 10^308 |

`LONGREAL` has IEEE double's precision and nearly its range, so most
programs compute the same results as on Unix. The differences:

- **No infinities, NaNs or denormals.** A real overflow, or a division by
  zero, is a fault: VMS stops the program with its message and a
  traceback, where Unix gives an infinity and goes on. A value too small
  to represent is 0.

      %SYSTEM-F-FLTOVF_F, arithmetic fault, floating overflow at PC=00002045, PSL=03C00000
      %TRACE-F-TRACEBACK, symbolic stack dump follows
      module name     routine name                     line       rel PC    abs PC

      OVF             OVF_INIT                                   00000045  00002045
      OVF             OVF_MAIN                                   00000006  00002071

- **Rounding.** The VAX rounds a result exactly halfway between two
  values away from zero, where IEEE rounds to even. A result can differ
  in its last bit. A constant poc folds and the same value computed at
  run time can differ so too.
- **Files still hold IEEE reals.** `Files`' typed riders write a `REAL` as
  IEEE single and a `LONGREAL` as IEEE double, the same bytes as on Unix,
  converting from and to the VAX formats, so a file written on one system
  reads on the other. A value too large for the VAX, or an infinity,
  reads as the largest VAX value of its sign. A NaN reads as the VAX's
  reserved operand, and arithmetic on it stops the program.
- **`Reals`**, which takes a real's bits apart, works with F_floating's
  and G_floating's fields.

### Integers

As on Unix, integer arithmetic wraps. A `DIV` or `MOD` by zero is a
trap, as it is on x86: VMS stops the program with its message,
`%SYSTEM-F-INTDIV, arithmetic trap, integer divide by zero`, and a
traceback. The traceback names a module's body `<MODULE>_INIT`, and a
procedure by its VAX symbol, at most 31 characters.

### When a program fails

A trap writes the same message as on Unix to `SYS$ERROR`, with the
position `-trap-location` adds, and ends the program. VMS's status is a
condition value, which DCL keeps in `$STATUS`. A trap with code *c* ends
with `%X10000000 + 8 * c + 2`: severity error, message number *c*, and
DCL's own message suppressed (bit 28), since poc's has said what happened.
`HALT(0)` ends with `SS$_NORMAL` (`%X00000001`), and `HALT(n)`, *n* from 1
to 255, with `%X10000000 + 8 * n + 2`, as a trap with code *n* does. A
procedure recovers *n* as `($STATUS .AND. %XFFF8) / 8`.

The codes and messages are the Unix ones (the *Reference Guide*'s table
of traps says what each covers), with one more, 15:

| Code | Message | `$STATUS` |
|---|---|---|
| 2 | `index out of range` | `%X10000012` |
| 3 | `no matching CASE label` | `%X1000001A` |
| 4 | `NIL pointer dereference` | `%X10000022` |
| 5 | `type guard failed` | `%X1000002A` |
| 6 | `no matching WITH guard` | `%X10000032` |
| 7 | `Too many, or negative number of, elements in dynamic array` | `%X1000003A` |
| 8 | `ENTIER argument out of range for LONGINT` | `%X10000042` |
| 9 | `open array assigned to an array too short for it` | `%X1000004A` |
| 10 | `assertion failed`, or `assertion failed (n)` | `%X10000052` |
| 11 | `heap exhausted: NEW cannot allocate the block` | `%X1000005A` |
| 12 | `function procedure reached its END without RETURN` | `%X10000062` |
| 13 | `record assigned to a variable whose dynamic type extends its static type` | `%X1000006A` |
| 14 | `SHORT argument out of range`, `CHR argument out of range` | `%X10000072` |
| 15 | `heap re-entered at AST level: import AsynchronousTraps` | `%X1000007A` |

Trap 15 is the VAX's alone: a program whose asynchronous system traps
allocate, and which does not import `AsynchronousTraps`, ends so.

    $ RUN TRAPS
    index out of range
    $ SHOW SYMBOL $STATUS
      $STATUS == "%X10000012"

### Files and their names

File names are VMS's: `DISK$USER:[ME.WORK]NOTES.TXT;3`, at most 39
characters of name and 39 of type, and each file has versions. `Files`
follows VMS where Unix would replace a file:

- `Files.Register` makes a new version. The file of that name stays, as
  the version below, where on Unix it would be replaced. `Files.Old` of
  the name finds the newest.
- `Texts.Close` keeps the old file as that older version, not as
  `<name>.Bak`.

The files `Files` makes are Stream_LF, written and read as bytes, as on
Unix. A file of another record format, such as the variable-length
records that EDT and most VMS programs write, is read a record at a
time, with an LF after each, so a program sees lines as on Unix. Writing
to an existing file is refused unless it is Stream_LF, fixed-length or
undefined. `Files`' search path is VMS directories, separated by
commas.

### Output

`Out` writes `SYS$OUTPUT` a record at a time: each `Out.Ln` ends one.
Text not yet ended by `Out.Ln` is written when the program ends, or
when `Out.Flush` writes it to a terminal without ending the line, which a
prompt needs. `In` reads `SYS$INPUT` a record at a time, as a line, and
when both are terminals shows `Out`'s unfinished line as its prompt.
`Err` writes `SYS$ERROR`, which is the terminal in an interactive
process, and the log in a batch job.

### The command line and the environment

A program's arguments, `Args` and `Modules.ArgVector`, come from a
foreign command's line. `RUN` passes none, so define a symbol for the
image, with a `$` before its file name:

    $ ECHO :== $DISK$USER:[ME.WORK]ECHO.EXE
    $ ECHO one "Two Words" three
    ONE
    Two Words
    THREE

DCL splits the line and turns it into capitals, except what is quoted.

`Platform.GetEnv(name, value)`, where Unix reads an environment variable,
translates the logical name `name`; if there is none, it reads the DCL
symbol of that name. VMS has no `HOME` or `USER`: the login directory is
the logical name `SYS$LOGIN`, and the user name is a job's
(`LIB$GETJPI`, chapter 9). `Platform.System` runs a DCL command in a
subprocess and returns 0 when its status is a success, as on Unix,
otherwise that status, a condition value, and -1 when no subprocess could
be made.

### Calling the system

The VAX back end refuses `["C"]` external procedures: VMS has no C
compiler in its base system, and its routines follow VMS's calling
standard. Declare them `["VMS"]` instead (chapter 7), or use the
declarations VMSDEF has already.

### What is not there yet

voc's library modules (the *User's Guide*, chapter 11), which poc for
Unix does not have either. `SYSTEM.CC`, `GETREG` and `PUTREG`. D_floating
and H_floating, and the vector and privileged system services
(appendix B).

## 6. The runtime modules on VMS

*For the Unix reader: which of the runtime's modules behave differently
on VMS, and how. For the VMS reader: what each of Oberon's own modules is
built on.*

The library `POCRTL` has the same modules as the runtime on Unix, with
the same interfaces, so a program written for them compiles for VMS
unchanged. The *Reference Guide*'s chapter 9 describes each one. This
chapter says what each is built on in VMS, and where it behaves
differently from Unix. Chapter 5 has already covered the differences
that most programs meet. `POCRTL` also has two modules that only VMS
has, described at the end of this chapter.

| Module | On VMS, built on | What differs |
|---|---|---|
| `Out`, `Err`, `Console` | `SYS$OUTPUT`, `SYS$ERROR` | A record for each `Ln` (chapter 5). `IsConsole` asks `$GETDVIW`. |
| `OutStr` | | Nothing. |
| `In`, `InStr` | `SYS$INPUT` | A record at a time, with `Out`'s unfinished line as the prompt (chapter 5). |
| `Args` | `LIB$GET_FOREIGN` | A foreign command's line, as DCL gives it (chapter 5). |
| `Modules` | `LIB$GET_FOREIGN`, `$GETJPI` | No `Init`. Only the modules linked into the program exist. |
| `Platform` | RMS, `$TRNLNM`, `LIB$GET_SYMBOL`, `LIB$SPAWN`, `$SETAST` | Statuses are VMS's. Time is local time. Only an interrupt handler is ever called. |
| `Directories` | `$PARSE`, `LIB$CREATE_DIR`, `$SETDDIR` | Directories as VMS writes them. |
| `Files` | RMS | Versions, and record formats (chapter 5). |
| `Texts`, `Oberon` | `Files` | `Texts.Close` keeps the old file as an older version. |
| `Strings` | | Reals convert to and from F_floating and G_floating. |
| `Reals` | | The fields are F_floating's and G_floating's. |
| `Math`, `MathL` | `MTH$`, `OTS$` | The constants are F_floating's and G_floating's. |
| `VT100` | `Out.Flush` | Each sequence reaches the terminal as it is sent. |
| `GarbageCollectedHeap` | `LIB$GET_VM`, `$DCLEXH` | The heap is limited by the paging file quota. |

### Files

`Files` on VMS keeps the model it has on Unix. A file is a sequence of
bytes, and the bytes a program writes come back as they were written.
Chapter 5 described versions and record formats. Beyond those:

- **`New` makes nothing on disk.** The first block written, or `Close`,
  or `Register`, creates the file under a temporary name,
  `POC_<process>_<n>.TMP`, in the default directory. `Register` then
  renames it to its own name as a new version. A program that stops half
  way leaves its temporary files behind, which can be deleted. `New("")`
  makes a file that never gets a name, and is deleted when the program
  no longer holds it.
- **`Old` opens a file only to read it**, and the first write opens it
  again to write. RMS sets a file's revision date whenever it is closed
  after being opened to write, so a file a program only reads keeps its
  date. Two `Old` calls for one file give two independent `File`s.
- **`Delete` deletes the highest version**, and the version below it
  becomes the one `Old` finds. `Rename`, like `Register`, makes a new
  version of the new name.
- **`Purge` empties a file**, as on Unix. It does not delete older
  versions the way DCL's `PURGE` does.
- **The search path** (`SetSearchPath`) is a list of directories
  separated by commas, such as `[.SRC],DUA1:[LIB]`. A logical name in it
  stands for the directory it translates to. A `~` at the start stands
  for `SYS$LOGIN`, so `~[.LIB]` is the directory `LIB` in the login
  directory. A name with `:`, `[` or `<` in it is found where it says,
  not on the path.
- **A name is given to RMS as it is.** Case does not matter in it, and a
  name with no version means the highest one. A name may have at most
  255 characters.
- **An error that cannot be reported to the caller**, such as a file
  that cannot be created or written, stops the program with a message
  and `HALT(99)`, as on Unix.

The program below writes two versions of `NOTES.TXT`, then deletes them
one at a time:

<!-- example: vax/versions/Versions.Mod -->
```
MODULE Versions;
  IMPORT Files, Out;

  VAR res: INTEGER;

  PROCEDURE Write(text: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; i: INTEGER;
  BEGIN
    f := Files.New("NOTES.TXT"); Files.Set(r, f, 0);
    i := 0;
    WHILE text[i] # 0X DO Files.Write(r, text[i]); INC(i) END;
    Files.Write(r, 0AX);
    Files.Register(f); Files.Close(f)
  END Write;

  PROCEDURE Show;
    VAR f: Files.File; r: Files.Rider; ch: CHAR;
  BEGIN
    f := Files.Old("NOTES.TXT");
    IF f = NIL THEN
      Out.String("no NOTES.TXT"); Out.Ln
    ELSE
      Files.Set(r, f, 0); Files.Read(r, ch);
      WHILE ~r.eof DO
        IF ch = 0AX THEN Out.Ln ELSE Out.Char(ch) END;
        Files.Read(r, ch)
      END;
      Files.Close(f)
    END
  END Show;

BEGIN
  Write("the first version");
  Write("the second version");
  Show;
  Files.Delete("NOTES.TXT", res); Show;
  Files.Delete("NOTES.TXT", res); Show
END Versions.
```

<!-- vax-session: versions -->

    $ RUN VERSIONS
    the second version
    the first version
    no NOTES.TXT

On Unix the same program prints `the second version` and then
`no NOTES.TXT` twice, since the second `Register` replaced the first
file.

### Platform

`Platform` is the layer under `Files`, `In`, `Out` and `Modules`, and
voc's programs call it directly. It has its whole interface on VMS, with
these differences:

- **An `ErrorCode` is a VMS status.** It is 0 for success, and otherwise
  the status of the service that failed: the whole longword under `-OC`,
  its low word under `-O2`, where an `INTEGER` is a word. The error
  tests, such as `Absent`, `NoSuchDirectory` and `Inaccessible`,
  recognize RMS's and the system services' statuses. `ConnectionFailed`
  and `Interrupted` are always `FALSE`: `Platform` makes no connections,
  and an AST does not make a system service fail.
- **Time is local time**, the only time VMS 5.5 keeps. `GetTimeOfDay`
  counts seconds from 1 January 1970 in local time, so its count differs
  from Unix's by the time zone's offset.
- **Files by handle** are those of a table of 32 files. `StdIn`, `StdOut`
  and `StdErr` are `SYS$INPUT`, `SYS$OUTPUT` and `SYS$ERROR`, and what is
  written to the last two comes out in order with `Out`'s and `Err`'s.
  `OldRW` refuses a file whose record format `Files` cannot write.
- **`GetEnv` and `System`** are as chapter 5 says. `GetEnv` translates a
  logical name, or else reads a DCL symbol. `System` runs a command in a
  subprocess.
- **`SetInterruptHandler`** installs a handler for CTRL/C, typed at the
  terminal `SYS$COMMAND` names. VMS calls the handler as an asynchronous
  system trap, with 2, Unix's `SIGINT`, as its argument, so it must
  follow chapter 14's rules for code that runs at AST level. A program
  with no handler is stopped by CTRL/C, as usual. `SetQuitHandler` and
  `SetBadInstructionHandler` accept a handler but never call it, since
  VMS sends a process no such signals.

### Modules and the command line

`Modules` gets the command line itself from VMS, with
`LIB$GET_FOREIGN`. There is no `Init`, which a program on Unix never
calls either. Argument 0 is the image's file specification, such as
`DUA1:[USERS.ME]ECHO.EXE;1`, as argument 0 on Unix is the program's
name. `BinaryDir` is the image's device and directory.

`ThisMod` and `ThisCommand` work as on Unix, over the modules linked
into the program. Each one's initializer registers it as it starts, so
`ThisMod` finds a module once its initialization has begun. `Free`
unloads nothing, as on Unix. `Halt` and `AssertFail` write voc's
messages to `SYS$ERROR` and end the program with the status chapter 5
gives for a trap.

### Reals and mathematics

`Strings`, `Texts` and `In` convert decimal text to the nearest
F_floating or G_floating value, rounding a tie to even, by the same exact
method poc uses for a real constant. `Out` writes a real's decimal digits
correctly rounded, as it does on Unix.

`Math` and `MathL` call VMS's own `MTH$` routines, and `OTS$`'s for a
power. Their errors are the same as on Unix: a domain error is checked
before the call, an overflow is reported to `ErrorHandler`, and each
function returns the same value in each case. Their constants describe
the VAX formats. `Math`'s `expoMin` and `expoMax` are -128 and 126, and
`MathL`'s are -1024 and 1022. The largest values are those in chapter
5's table. `exponent`, `fraction`, `scale`, `ulp`, `succ` and `pred`
work on F_floating's and G_floating's own fields, and are exact.

### The heap

`NEW` allocates from the same collector as on Unix, which takes its
memory from `LIB$GET_VM`. The heap stops growing at three quarters of
the paging file quota the process has left when the program starts, so
a collection runs before VMS refuses the memory. A process with a small
`PGFLQUOTA` therefore has a small heap. `SHOW PROCESS/QUOTAS` shows how
much it has left. When the heap is full, `NEW` leaves its pointer `NIL`,
or traps with `-trap-heap-exhausted`, as on Unix.

Finalizers (`GarbageCollectedHeap.RegisterFinalizer`) run at the end of
the program from an exit handler, `$DCLEXH`. A program's own exit
handler that calls `$EXIT` skips the handlers declared before it, poc's
included, so files would then be left unwritten (chapter 8's
`ExitHandlers`).

In a program that imports `AsynchronousTraps`, the heap disables ASTs
while it allocates or collects, so `NEW` is safe at AST level (chapter
14).

### Two modules VMS alone has

- **`VmsArguments`** has the structures a program builds to call VMS: a
  string descriptor, item lists, an I/O status block and a lock status
  block, with procedures that fill them (chapter 7).
- **`AsynchronousTraps`** makes an Oberon procedure an AST routine, and
  lets the main program disable and restore AST delivery around data
  that it shares with one (chapter 14).

## 7. Calling VMS

*For both kinds of reader: the Unix reader meets VMS's argument
conventions here, and the VMS reader sees them in Oberon.*

A VMS program does most of its work by calling VMS: the system services
(`SYS$`), the run-time library (`LIB$`, `STR$`, `SMG$`, `SOR$` and the
rest), and RMS. poc reaches them at three levels, and a program can mix
them freely:

1. **VMSLIB**, a dozen small Oberon modules for what most programs need:
   condition values, logical names, DCL symbols, dates, subprocesses and
   so on (chapter 8). Use them where they cover what you need.
2. **VMSDEF**, VMS's own interfaces as Oberon modules, generated from the
   definitions VMS keeps for every language (`SYS$LIBRARY:STARLETSD.TLB`):
   one module for each of its 65, such as `STARLET` (the system
   services), `LIB_ROUTINES`, `SSDEF` (the system's status codes) and
   `LNMDEF` (logical names). Every routine, constant and structure has
   the name the VMS manuals give it.
3. **A declaration of your own**, a `["VMS"]` procedure, for a routine
   VMSDEF does not have, or to give one a shape that suits your program.

This chapter takes one task, finding what a logical name stands for,
through all three, and then says exactly how a `["VMS"]` procedure passes
its arguments.

### Through VMSLIB

`LogicalNames.Translate` looks a name up in a table and gives its first
equivalence string:

<!-- example: vax/wherelogin/WhereLogin.Mod -->
```
MODULE WhereLogin;
  IMPORT SYSTEM, Out, LogicalNames, Conditions;
  VAR value, text: ARRAY 256 OF CHAR; status: SYSTEM.INT32;
BEGIN
  status := LogicalNames.Translate(LogicalNames.Job, "SYS$LOGIN", value);
  IF Conditions.Succeeded(status) THEN
    Out.String(value); Out.Ln
  ELSE
    Conditions.Message(status, text); Out.String(text); Out.Ln
  END
END WhereLogin.
```

<!-- vax-session: wherelogin -->

    $ POC WHERELOGIN.MOD
    $ @WHERELOGIN
    $ RUN WHERELOGIN
    DUA1:[USERS.POC]

Like nearly every procedure that calls VMS, `Translate` returns VMS's
**condition value**, a longword whose low bit is set for success. Test it
with `Conditions.Succeeded` (or `ODD(status)`), and turn one into its
message text with `Conditions.Message`, which is how VMS prints it:

    %SYSTEM-F-NOLOGNAM, no logical name match

Compare a status with a particular condition by its name in VMSDEF's
message modules: `status = SSDEF.SS$_NOLOGNAM`.

### Through VMSDEF

`LogicalNames` is built on `$TRNLNM`, which `STARLET` declares as VMS
defines it:

    PROCEDURE ["VMS", "SYS$TRNLNM"] SYS$TRNLNM*(
        ATTR-: SYSTEM.CARD32; (* MASK_LONGWORD, optional: NIL omits it *)
        TABNAM-: ARRAY OF CHAR; (* LOGICAL_NAME *)
        LOGNAM-: ARRAY OF CHAR; (* LOGICAL_NAME *)
        ACMODE-: SYSTEM.CARD8; (* ACCESS_MODE, optional: NIL omits it *)
        ITMLST-: ARRAY OF SYSTEM.BYTE (* ITEM_LIST, optional: NIL omits it *)
      ): SYSTEM.INT32; (* COND_VALUE *)

The comments are VMS's: each argument's VMS type, from the manual's
"VMS Usage" line, and whether it may be left out. `$TRNLNM` returns what
it finds through an **item list**, an array of entries that each name an
item code, a buffer for the answer, and a word for its length, ended by a
longword 0. `VmsArguments` has the entry's type and two procedures to fill
a list:

<!-- example: vax/wherelogin/WhereLogin2.Mod -->
```
MODULE WhereLogin2;
  IMPORT SYSTEM, Out, VmsArguments, STARLET, LNMDEF, Conditions;
  VAR
    items: ARRAY 2 OF VmsArguments.ItemListEntry3;
    value: ARRAY LNMDEF.LNM$C_NAMLENGTH + 1 OF CHAR;
    length: SYSTEM.CARD16;
    status: SYSTEM.INT32;
    text: ARRAY 256 OF CHAR;
BEGIN
  VmsArguments.SetItem(items, 0, LNMDEF.LNM$_STRING, value, length);
  VmsArguments.EndList(items, 1);
  status := STARLET.SYS$TRNLNM(NIL, "LNM$JOB", "SYS$LOGIN", NIL, items);
  IF Conditions.Succeeded(status) THEN
    value[length] := 0X;
    Out.String(value); Out.Ln
  ELSE
    Conditions.Message(status, text); Out.String(text); Out.Ln
  END
END WhereLogin2.
```

Three things to see in it:

- **`NIL` leaves an argument out.** `ATTR` and `ACMODE` are optional, and
  `NIL` passes the 0 that VMS takes as "omitted". The word `NIL` itself
  is needed: a constant declared `= NIL` is not taken so.
- **VMS does not end a string with 0X.** It gives the length instead, in
  the word the item names. A program that wants an Oberon string puts the
  0X there itself, as `value[length] := 0X` does, and makes the buffer
  one longer than the longest answer.
- **The buffers stay put.** An item list holds the addresses of `value`
  and `length`, so they must still be where they were when the call is
  made: global variables, or local ones of the procedure that makes the
  call, never a value parameter of a procedure that fills the list.

### A declaration of your own

A `["VMS"]` procedure with no body declares a routine VMS supplies. The
first string names the convention, the second the routine's name, which
poc writes as it is:

    PROCEDURE ["VMS", "LIB$GET_SYMBOL"] GetSymbol(
        symbol-: ARRAY OF CHAR;
        VAR resultant: ARRAY OF CHAR;
        VAR resultantLength: SYSTEM.CARD16;
        VAR tableType: LONGINT): LONGINT;

Write one when VMSDEF lacks the routine, or when a narrower declaration
reads better in your program: here `GetSymbol` leaves out no argument, so
it needs no `NIL`. The Oberon name is yours; the linker sees only
`LIB$GET_SYMBOL`. Any number of declarations may name the same routine.

### How each argument is passed

VMS routines take each argument in one of three ways, which the VMS
manuals call its **mechanism**: by value, by reference (its address), or
by descriptor (the address of a small structure giving a string's
length, kind and address). In a `["VMS"]` declaration the formal
parameter decides which:

| The formal parameter | VMS receives | The actual argument |
|---|---|---|
| a value parameter of at most a longword (`LONGINT` under `-O2`, a `SYSTEM.CARD32`, a pointer, a `SET`, ...) | the value | any expression of its type |
| a `VAR` parameter | its address | a variable |
| a read-only parameter, `x-` | its address | any expression: a variable is passed itself, anything else from a copy poc makes |
| an `x-` `ARRAY OF SYSTEM.BYTE` | its address | anything at all: a record, an array, a scalar |
| an open `ARRAY OF CHAR`, `x-` | a descriptor, class S, of the string up to its 0X | a string or a character array |
| an open `ARRAY OF CHAR`, `VAR` | a descriptor, class S, of the whole array, for VMS to fill | a character array |
| a procedure type | the procedure's address, to be called back | a global Oberon procedure |

So a VMS argument described as "by reference, read only" is an `x-`
parameter, "by reference, write only" or "modify" a `VAR` one, and "by
descriptor" an open `ARRAY OF CHAR`. `NIL` omits any argument passed by
reference or by descriptor.

A value parameter wider than a longword is an error, since VMS passes
nothing wider by value: declare a quadword, such as a time, as `x-` or
`VAR` (`time-: HUGEINT`). Under `-OC` that includes `LONGINT`, which is
8 bytes there; VMSDEF's declarations use the exact-width types
(`SYSTEM.INT32`, `SYSTEM.CARD16`, ...) so that they mean the same under
both size models, and a declaration of your own should too.

A routine that returns a descriptor, or takes one inside a structure or
an item list, needs one built by hand: `VmsArguments.Describe` makes a
`StringDescriptor` for a character array, and `DescribeArray` an array
descriptor for an array of strings (such as a menu's choices for
`SMG$CREATE_MENU`); pass it as `SYSTEM.ADR(descriptor)` to a parameter of
type `SYSTEM.ADDRESS`.

### Callbacks

Some routines call a routine of the program's: `LIB$TRAVERSE_TREE` calls
one for each node, `SOR$` one to compare two records, a system service
one when it completes (an AST, chapter 14). Declare the parameter with a
procedure type, and pass a global procedure whose parameters follow the
same rules as above:

    TYPE Action = PROCEDURE (node, data: SYSTEM.ADDRESS): LONGINT;

A nested or type-bound procedure cannot be passed. VMSLIB's
`BalancedTrees` and `SortMerge` wrap the two commonest callbacks so that
a program need not write one.

### What VMS returns

A routine declared with a result returns VMS's condition value in R0, as
`SYSTEM.INT32` in VMSDEF. A few return something else - `LIB$GET_EF`'s
event flag, `LIB$GETJPI`'s answer - through a `VAR` parameter, with the
condition value still the result. A routine that *signals* an error
instead of returning it (most of `STR$` and `MTH$`) stops the program
with VMS's message unless a handler catches it; chapter 13 shows how, and
VMSLIB's `DecimalStrings` turns `STR$`'s signals back into returned
statuses with `LIB$SIG_TO_RET`.

## 8. VMSLIB

*For both kinds of reader: what each of VMSLIB's modules does, and when
to reach past it to VMSDEF.*

VMSLIB is twelve small Oberon modules over the parts of VMS that most
programs need. Each is written by hand over VMSDEF's declarations, and
gives VMS's facilities Oberon's types: a string is an `ARRAY OF CHAR`, a
time a `HUGEINT`, a callback an Oberon procedure. It comes in the STARLET
kit (chapter 1) and is a library like any other, so a program that
imports one of its modules links it, from its object library or, with
`-shared-libraries`, its shareable image (chapter 3).

| Module | For | Built on | More in |
|---|---|---|---|
| `Conditions` | Condition values, their messages, signals and handlers | `$GETMSG`, `LIB$SIGNAL`, `LIB$STOP`, `LIB$ESTABLISH` | chapter 13 |
| `LogicalNames` | Defining, deassigning and translating logical names | `$CRELNM`, `$DELLNM`, `$TRNLNM`, `LIB$SET_LOGICAL` | chapter 7 |
| `Symbols` | DCL symbols | `LIB$GET_SYMBOL`, `LIB$SET_SYMBOL`, `LIB$DELETE_SYMBOL` | |
| `CommandLanguage` | A command's parameters and qualifiers, as DCL parses them | `CLI$` | chapter 10 |
| `DateTimes` | VMS's dates and times | `$GETTIM`, `$BINTIM`, `$ASCTIM`, `LIB$` | |
| `DecimalStrings` | Exact decimal arithmetic of up to 255 digits | `STR$` | |
| `BalancedTrees` | Balanced binary trees of the program's records | `LIB$INSERT_TREE`, `LIB$LOOKUP_TREE`, `LIB$TRAVERSE_TREE` | |
| `SortMerge` | SORT's constants and keys | `SORTSHR` | chapter 9 |
| `EventFlags` | Local event flags | `LIB$GET_EF`, `$SETEF`, `$WAITFR` | chapter 14 |
| `Timers` | A routine called after a time, and sleeping | `$SETIMR`, `$CANTIM`, `$HIBER` | chapter 14 |
| `Subprocesses` | DCL commands in a subprocess | `LIB$SPAWN` | chapter 15 |
| `ExitHandlers` | Procedures called when the program exits | `$DCLEXH` | |

The modules share three conventions:

- **A procedure that calls VMS returns VMS's condition value**, a
  `SYSTEM.INT32`, which `Conditions.Succeeded` (or `ODD`) tests and
  `Conditions.Message` turns into text (chapter 7). VMSDEF's message
  modules name each one: `SSDEF.SS$_NORMAL`, `LIBDEF.LIB$_KEYALRINS`.
- **A string it returns** is cut to fit its array, less one character,
  and ends with `0X`.
- **A string it is given** is passed up to its `0X`.

When VMSLIB lacks something, VMSDEF has every routine VMS declares
(chapter 9), and a program can use both.

### Conditions

A condition value is a longword with a severity in its low three bits,
a message number above them and a facility number above that.
`Conditions` takes one apart (`Succeeded`, `Severity`, `MessageNumber`,
`Facility`), and gives its text, as VMS prints it, by `Message`:

    %SYSTEM-F-ABORT, abort

`Signal` signals a condition, as `LIB$SIGNAL` does. Unless a handler
deals with it, VMS prints its message and a traceback to `SYS$ERROR` and
goes on, unless the severity is `Severe`, which ends the program. `Stop`
signals one that cannot go on, and never returns. `SignalWith` and
`StopWith` add one argument for the message's FAO directive, and
`SignalList` and `StopList` take a whole argument list: several FAO
arguments, or one condition chained to another. `Establish`, `Revert`
and `Unwind` give a procedure a condition handler of its own (chapter
13).

### LogicalNames and Symbols

`LogicalNames` defines, deassigns and translates a logical name in a
table (`Process`, `Job`, `Group`, `System`, or `FileDevice`, the search
list DCL uses for a file name) and an access mode:

    status := LogicalNames.Define(LogicalNames.Process, "REPORTS", "DUA1:[ME.REPORTS]",
      LogicalNames.Supervisor);
    status := LogicalNames.Translate(LogicalNames.Process, "REPORTS", value);

The mode chooses how long a name lasts:

- **A `Supervisor` name** is made by `LIB$SET_LOGICAL`, as DCL's
  `DEFINE` makes it, and outlives the program.
- **A `User` name** is deleted when the program ends.
- **An `Executive` or `Kernel` name** needs the privilege `SYSNAM`.
  Without it, the request makes a `User` name.

The group and system tables need privileges too. A translation ignores
case, as DCL's does. `TranslateAt` gives each equivalence string of a
search list in turn, and the index of the last.

`Symbols` gets, sets and deletes a DCL symbol, `Local` or `Global`. A
symbol's value is a string here, a number's its decimal text. `Get` looks
in the local table first and then the global one, and says where it found
the name:

    status := Symbols.Set("RESULT", "42", Symbols.Global);
    status := Symbols.Get("RESULT", value, table);

Both need DCL, so `Symbols`, and `LogicalNames` with `Supervisor`, return
`LIB$_NOCLI` in a process that has none, such as a subprocess run without
a command line or a detached process. For a program that is not only for
VMS, `Platform.GetEnv` translates a logical name, or else reads a DCL
symbol, as on Unix it reads an environment variable (chapter 5).

### DateTimes

A VMS time is a quadword of 100-nanosecond units, a `HUGEINT` here
(`DateTimes.Time`). An absolute time counts from 17 November 1858 and is
positive. A delta time, a length of time, is negative. `Now` gives the
time, `FromText` and `ToText` convert both kinds to and from VMS's
standard text, `Add` and `Subtract` combine them, `Delta` makes a delta
of so many weeks, days, hours, minutes or seconds, and `Part` and
`DayOfWeek` take one apart:

<!-- example: vax/dates/Dates.Mod -->
```
MODULE Dates;
  IMPORT SYSTEM, Out, DateTimes, LIBDTDEF;
  VAR
    start, week, later: DateTimes.Time;
    julian, status: SYSTEM.INT32;
    text: ARRAY 32 OF CHAR;
BEGIN
  status := DateTimes.FromText("16-OCT-2026 12:34:56.78", start);
  status := DateTimes.Delta(LIBDTDEF.LIB$K_DELTA_WEEKS, 1, week);
  status := DateTimes.Add(start, week, later);
  DateTimes.ToText(later, text);
  Out.String(text); Out.Ln;
  Out.String("day of the week: "); Out.Int(DateTimes.DayOfWeek(later), 0); Out.Ln;
  status := DateTimes.Part(LIBDTDEF.LIB$K_JULIAN_DATE, later, julian);
  Out.String("day number: "); Out.Int(julian, 0); Out.Ln
END Dates.
```

<!-- vax-session: dates -->

    $ RUN DATES
    23-OCT-2026 12:34:56.78
    day of the week: 5
    day number: 61336

`DayOfWeek` counts from 1 for Monday. The day number is the Julian day
VMS counts from 17 November 1858. `LIBDTDEF`, a VMSDEF module, names the
units and parts.

`Format` formats a time as `LIB$FORMAT_DATE_TIME` does, in the language
and format the logical names `SYS$LANGUAGE` and `LIB$DT_FORMAT` choose,
or in one a program sets with `LIB$INIT_DATE_TIME_CONTEXT` on the context
it passes. A program that runs on Unix too should use `Oberon.Time` or
`Platform.GetClock` instead.

### DecimalStrings

`STR$`'s decimal arithmetic is exact for numbers of up to 255 digits,
which is what money and other counting want. A `Decimal` is a number as
`STR$` gives it: a sign, the exponent of ten, and the digits as text.
`FromText`, `FromInteger` and `ToText` convert, and `Add`, `Subtract`,
`Multiply`, `Divide`, `Reciprocal` and `Round` compute:

<!-- example: vax/factorial/Factorial.Mod -->
```
MODULE Factorial;
  IMPORT SYSTEM, Out, Conditions, DecimalStrings;
  VAR
    product, factor: DecimalStrings.Decimal;
    i: INTEGER;
    status: SYSTEM.INT32;
    text: ARRAY 300 OF CHAR;
BEGIN
  DecimalStrings.FromInteger(1, product);
  i := 2; status := 1;
  WHILE (i <= 50) & Conditions.Succeeded(status) DO
    DecimalStrings.FromInteger(i, factor);
    status := DecimalStrings.Multiply(product, factor, product);
    INC(i)
  END;
  IF Conditions.Succeeded(status) THEN
    DecimalStrings.ToText(product, text)
  ELSE
    Conditions.Message(status, text)
  END;
  Out.String("50! = "); Out.String(text); Out.Ln
END Factorial.
```

<!-- vax-session: factorial -->

    $ RUN FACTORIAL
    50! = 30414093201713378043612608166064768844377641568960512000000000000

Each arithmetic procedure returns `STR$`'s status:

- **`SS$_NORMAL`** when the result is exact.
- **`STR$_TRU`** when it would need more than 255 digits.
- **A condition `STR$` would have signalled**, such as `STR$_DIVBY_ZER`,
  which is severe. It is returned here, not signalled, so it does not
  end the program.

After any status but `SS$_NORMAL` the result is not the value.

`Divide`'s digits are those after the decimal point, and `Round`'s
places are significant digits: 123456.789 rounded to 2 is 120000. The
module returns signals as statuses by a handler of its own, so it is not
for AST routines.

### BalancedTrees

`LIB$`'s balanced binary trees keep records in order of a key and find
one quickly. The records are the program's own: a program extends
`BalancedTrees.NodeDesc` with its key and data, makes each node by `NEW`,
and gives `Insert`, `Lookup` and `Traverse` a comparison of its own.
`NodeDesc` is `LIB$`'s node header, so the collector traces the links
`LIB$` writes, and a node lives as long as its tree does.

<!-- example: vax/words/Words.Mod -->
```
MODULE Words;
  IMPORT SYSTEM, Out, BalancedTrees, LIBDEF;

  TYPE
    Word = POINTER TO WordDesc;
    WordDesc = RECORD (BalancedTrees.NodeDesc)
      text: ARRAY 16 OF CHAR;
      count: INTEGER
    END;

  VAR
    tree: BalancedTrees.Tree;
    status: SYSTEM.INT32;

  PROCEDURE Compare(a, b: BalancedTrees.Node): LONGINT;
  BEGIN
    IF a(Word).text < b(Word).text THEN RETURN -1
    ELSIF a(Word).text = b(Word).text THEN RETURN 0
    ELSE RETURN 1
    END
  END Compare;

  PROCEDURE Add(text: ARRAY OF CHAR);
    VAR w: Word; found: BalancedTrees.Node; status: SYSTEM.INT32;
  BEGIN
    NEW(w); COPY(text, w.text); w.count := 1;
    status := BalancedTrees.Insert(tree, w, Compare, FALSE, found);
    IF status = LIBDEF.LIB$_KEYALRINS THEN INC(found(Word).count) END
  END Add;

  PROCEDURE Print(n: BalancedTrees.Node): BOOLEAN;
  BEGIN
    Out.String(n(Word).text); Out.Char(" "); Out.Int(n(Word).count, 0); Out.Ln;
    RETURN TRUE
  END Print;

BEGIN
  Add("the"); Add("quick"); Add("brown"); Add("fox"); Add("jumps");
  Add("over"); Add("the"); Add("lazy"); Add("dog"); Add("the");
  status := BalancedTrees.Traverse(tree, Print)
END Words.
```

<!-- vax-session: words -->

    $ RUN WORDS
    brown 1
    dog 1
    fox 1
    jumps 1
    lazy 1
    over 1
    quick 1
    the 3

`Insert` with duplicates `FALSE` refuses a node equal to one already in
the tree. It returns `LIB$_KEYALRINS` and that node in `found`, and the
new node is not linked in. With duplicates `TRUE` it links in each one.
`Lookup` takes a node of the program's type with its key filled, and
returns the node equal to it, or `NIL`. `Traverse` stops when the action
returns `FALSE`.

### SortMerge

SORT, VMS's sort and merge utility, can be called from a program: `SOR$`
in VMSDEF's `SOR_ROUTINES` (chapter 9). It sorts files, or records the
program passes it one at a time, by keys a program describes in a key
buffer. `SortMerge` has what VMSDEF does not: SORT's options, sort
processes and statistic codes, which VMS defines only in its shareable
image, and `AddKey`, which adds a key to a key buffer. This sorts a file
of 24-character records by the department in characters 12 to 17, then
by the salary in 18 to 23, highest first:

    keys[0] := 0;
    SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_T, SortMerge.ascending, 12, 6);
    SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_NU, SortMerge.descending, 18, 6);
    status := SOR_ROUTINES.SOR$PASS_FILES("STAFF.DAT", "STAFF.SRT",
      NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL);
    status := SOR_ROUTINES.SOR$BEGIN_SORT(keys, NIL, SortMerge.stable, NIL, 0, 0,
      NIL, NIL, NIL);
    status := SOR_ROUTINES.SOR$SORT_MERGE(NIL);
    status := SOR_ROUTINES.SOR$END_SORT(NIL);

`keys` is an `ARRAY 9 OF SYSTEM.CARD16`: a count, then four words for
each key. `stable` keeps records with equal keys in their input order.
SORT keeps the input file's record format, so a file `Files` wrote is
sorted into another that `Files` can read.

### EventFlags and Timers

A process has 64 local event flags. A system service that completes
later sets one when it does, and a program waits for it. `EventFlags.Get`
gives a program a flag no other part of it is using, and `Free` gives it
back. `Set`, `Clear`, `IsSet`, `Wait` and `WaitAny` work on flags.

`Timers.After` has VMS call an Oberon procedure, as an asynchronous
system trap, after so many milliseconds. `Cancel` cancels it, and `Sleep`
makes the process hibernate for a time. Chapter 14 says how a program
shares data safely with a procedure called so. This waits for a timer:

    status := EventFlags.Get(flag);
    status := EventFlags.Clear(flag);
    status := Timers.After(100, Fired, 42);
    status := EventFlags.Wait(flag);
    status := EventFlags.Free(flag)

where `Fired(parameter: SYSTEM.CARD32)`, called with 42, sets `flag`.

### Subprocesses

`Subprocesses.Run` runs a DCL command in a subprocess and waits for it.
It returns whether the subprocess could be made, and the command's final
status comes back in `completion`. `Start` starts one and does not wait,
and `Done`, `Wait` and `Stop` follow it:

    status := Subprocesses.Run("DIRECTORY/SIZE", "", "DIR.LIS", {}, completion);

Each takes an input and an output file (`""` for the program's own), and
options that keep the program's symbols, logical names or keypad from the
subprocess. A process may have only as many subprocesses at once as its
quota `PRCLM` allows, and one that has ended counts until VMS has
deleted it. Chapter 15 has the rest.

### ExitHandlers

`ExitHandlers.Declare` has VMS call a procedure when the program exits,
however it does: normally, by `$EXIT`, by a trap or by a severe
condition. The handler gets the exit status:

    PROCEDURE AtExit(VAR status: SYSTEM.CARD32);
    BEGIN
      Out.String("exiting"); Out.Ln
    END AtExit;
    ...
    status := ExitHandlers.Declare(AtExit);

Handlers run last declared, first called, and before poc's own, so
`Out`'s last line and the finalizers still come after them. Changing
`status` changes nothing. A handler that calls `$EXIT` ends the program
there: the handlers not yet called are skipped, poc's own among them, so
`Out`'s unfinished line is lost and no finalizer runs.

### CommandLanguage

A VMS program can have its command line parsed by DCL, as DCL's own
commands are: its qualifiers checked, its parameters prompted for, and
each asked for by name. `CommandLanguage` asks for them (`IsPresent`,
`Presence`, `GetValue`), in a program run as a verb defined by `SET
COMMAND`, or one that parses its own line with a command table
compiled from a `.cld` file. Chapter 10 has the whole of it.

## 9. The supported routines in VMSDEF

*For both kinds of reader: what VMSDEF holds, how to find a routine or a
constant in it, and which parts have been tried on a VAX.*

VMSDEF is VMS's own definitions as Oberon modules. VMS keeps one
description of its interfaces, written in SDL, for every language
(`SYS$LIBRARY:STARLETSD.TLB`): MACRO's `$xxxDEF` macros and VAX C's
header files are made from it. VMSDEF was made from it too, by poc's
generator, so it has every system service, every run-time library
routine SDL describes, and every constant and structure, under the names
the VMS manuals use.

### What is in it

`STARLETSD.TLB` holds 65 library modules, and those hold 243 SDL
modules. VMSDEF has one Oberon module for each, named as SDL names it,
without its leading `$`, and with `_` for a `$` inside the name:

| Kind | Modules | What they hold |
|---|---|---|
| Routines | `STARLET` (the system services), `LIB_ROUTINES`, `STR_ROUTINES`, `SMG_ROUTINES`, `SOR_ROUTINES`, `OTS_ROUTINES`, `MTH_ROUTINES`, `NCS_ROUTINES`, `PPL_ROUTINES`, `DTK_ROUTINES` | `["VMS"]` declarations: `STARLET.SYS$TRNLNM`, `LIB_ROUTINES.LIB$GETSYI`. |
| Condition values | `SSDEF`, `RMSDEF`, `LIBDEF`, `STRDEF`, `CLIMSGDEF`, `SMGMSG` ... | `SSDEF.SS$_NORMAL`, `RMSDEF.RMS$_FNF`. |
| Definitions | `FABDEF`, `RABDEF`, `IODEF`, `JPIDEF`, `SYIDEF`, `DVIDEF`, `LNMDEF`, `DSCDEF` ... | Item codes, function codes, masks and record types. |

A routine module's declaration says what VMS takes, argument by
argument, in the comments the generator writes from SDL:

    PROCEDURE ["VMS", "LIB$GETSYI"] LIB$GETSYI*(
        item_code-: SYSTEM.INT32; (* longword_signed *)
        VAR resultant_value: ARRAY OF SYSTEM.BYTE; (* varying_arg, optional: NIL omits it *)
        VAR resultant_string: ARRAY OF CHAR; (* char_string, optional: NIL omits it *)
        VAR resultant_length: SYSTEM.CARD16; (* word_unsigned, optional: NIL omits it *)
        VAR cluster_system_id: SYSTEM.CARD32; (* identifier, optional: NIL omits it *)
        node_name-: ARRAY OF CHAR (* char_string, optional: NIL omits it *)
      ): SYSTEM.INT32; (* cond_value *)

Each comment is the argument's VMS usage from the manual, and whether it
may be left out. Chapter 7 says how each kind of argument is passed. Here
is the declaration in use:

<!-- example: vax/systeminfo/SystemInfo.Mod -->
```
MODULE SystemInfo;
  IMPORT SYSTEM, Out, LIB_ROUTINES, SYIDEF, Conditions;

  (* the system's string item, by LIB$GETSYI *)
  PROCEDURE Show(label: ARRAY OF CHAR; item: SYSTEM.INT32);
    VAR text: ARRAY 64 OF CHAR; length: SYSTEM.CARD16; status: SYSTEM.INT32;
  BEGIN
    length := 0;
    status := LIB_ROUTINES.LIB$GETSYI(item, NIL, text, length, NIL, NIL);
    IF Conditions.Succeeded(status) THEN
      text[SYSTEM.VAL(INTEGER, length)] := 0X
    ELSE
      Conditions.Message(status, text)
    END;
    Out.String(label); Out.String(": "); Out.String(text); Out.Ln
  END Show;

BEGIN
  Show("VMS", SYIDEF.SYI$_VERSION);
  Show("hardware", SYIDEF.SYI$_HW_NAME)
END SystemInfo.
```

<!-- vax-session: systeminfo -->

    $ RUN SYSTEMINFO
    VMS: V5.5-2H4
    hardware: VAXserver 3900 Series

### Finding a routine or a constant

Look a routine up in the VMS manual for its facility, then in VMSDEF's
module for it: `SYS$` routines in `STARLET`, `LIB$` in `LIB_ROUTINES`,
and so on. A constant or a record type is in the module named for its
prefix, as the manual's `$xxxDEF` macro names it: `SYI$_VERSION` in
`SYIDEF`, `FAB$L_FOP` in `FABDEF`. A condition value is in its
facility's message module, such as `SS$_NOPRIV` in `SSDEF`.

The modules' sources come with the STARLET kit, in `[.SRC.RTL.VMS]`, and
are in `rtl/vax/vms` in poc's source tree. `poc -show-interface` prints a
module's interface without the comments:

    $ POC -SHOW-INTERFACE [.SRC.RTL.VMS]SYIDEF.MOD

### Records

A structure is a record type named for the structure, with fields named
as the manual names them, so a FAB is `FABDEF.FABDEF`, and its fields
are `FAB$B_FAC`, `FAB$L_FNA` and so on. Its layout is SDL's, checked when
the modules were made. The module also has each field's offset as a
constant, as MACRO's macros give it (`FABDEF.FAB$L_FOP = 4`). A flag
field's bits have constants too: `FAB$V_DLT`, the bit's position, and
`FAB$M_DLT`, its mask, with `$S_` for the width of a field of more than
one bit:

    parts.FAB$B_ORG := FABDEF.FAB$C_IDX;
    parts.FAB$B_RFM := FABDEF.FAB$C_FIX;
    parts.FAB$L_FOP := FABDEF.FAB$M_DLT;

What an Oberon record cannot express, VMSDEF gives as bytes and
constants:

- **A union** is its first member that fills it, such as `FAB$L_FOP`.
  The other members are only constants.
- **Bit fields** outside a union are an array of bytes, named after the
  first, and are set through their `$M_` masks.
- **A field not at its natural alignment**, as `XAB$L_RVB` at offset 14,
  is an array of bytes. A program reaches it with `SYSTEM.GET` and
  `SYSTEM.PUT` at its offset constant.

Chapter 11 builds RMS's control blocks this way.

### What has been tried on a VAX

"Generated" is not "supported". VMSDEF has more than 900 routines, and
each declaration is as SDL describes it, but only some have fixtures in
poc's test suite that call the real routine on a VAX and check what it
returns:

| Facility | Supported | Where |
|---|---|---|
| System services | Logical names (`$TRNLNM`, `$CRELNM`, `$DELLNM`); information by item list (`$GETJPIW`, `$GETSYIW`, `$GETDVIW`); time (`$GETTIM`, `$BINTIM`, `$ASCTIM`, `$NUMTIM`); messages (`$GETMSG`, `$FAOL`); I/O on a channel (`$ASSIGN`, `$QIOW`, `$DASSGN`, `$CREMBX`); event flags; locks (`$ENQW`, `$DEQ`); `$HIBER`, `$WAKE`, `$SETPRN`; timers and ASTs (`$SETIMR`, `$CANTIM`, `$DCLAST`, `$SETAST`); exit handlers (`$DCLEXH`) | chapters 7, 8, 14 |
| RMS | Indexed and relative files: `$CREATE`, `$OPEN`, `$CONNECT`, `$PUT`, `$GET`, `$FIND`, `$UPDATE`, `$DELETE`, `$REWIND`, `$CLOSE`, keyed access, with `FAB`, `RAB` and `XABKEY` | chapter 11 |
| `LIB$` | Symbols and logical names, `LIB$GETJPI`, `LIB$GETSYI`, `LIB$GETDVI`, `LIB$GETQUI`, dates and times, event flags, balanced trees, the interlocked queue and bit routines, `LIB$SPAWN` and process control, the condition routines, `LIB$CALLG` | chapters 8, 13, 15 |
| `SMG$` | Pasteboards, virtual displays and keyboards, renditions, reading keys and strings, menus | chapter 12 |
| `SOR$` | Sorting and merging files, and records the program passes, with its own comparison routine | chapter 8 |
| `STR$` | The decimal arithmetic: `STR$ADD`, `STR$MUL`, `STR$DIVIDE`, `STR$RECIP`, `STR$ROUND` | chapter 8 |
| `CLI$` | `CLI$DCL_PARSE`, `CLI$PRESENT`, `CLI$GET_VALUE` | chapter 10 |
| `MTH$`, `OTS$` | The F_floating and G_floating functions that `Math` and `MathL` use | chapter 6 |

Everything else is likely to work, since it was generated by the same
rules from the same description, but nothing has checked it. Treat a
routine outside this table as you would a declaration of your own: try
it, and check its status.

### What is left out

A few entries are not declared at all, each with a comment in its
module saying why:

- **A routine that takes a variable number of arguments**: `SYS$FAO`,
  and `LIB$` and `STR$` routines with a `LIST` argument, such as
  `LIB$SIGNAL`, `LIB$STOP` and `STR$CONCAT`. `Conditions` has
  `Signal`, `Stop` and `SignalList` for the first two. `SYS$FAOL`, which
  takes its arguments as an array, serves for `SYS$FAO`, and a
  declaration of your own with a fixed number of arguments serves too
  (chapter 7).
- **D_floating, H_floating and complex numbers**, which poc has no type
  for: the entries of `MTH$` that take or return them.
- **DECthreads**, the module `CMA`, whose types SDL does not name.

Appendix B lists the facilities left out altogether, such as the
privileged and vector services, and why.

## 10. Commands with qualifiers

*For the Unix reader: how a VMS command line is defined and parsed, which
is nothing like `argv`. For the VMS reader: the Command Definition
Utility's tables and the `CLI$` routines, from Oberon.*

A DCL command is a verb, its parameters and its qualifiers:
`COPY/LOG A.TXT B.TXT`, `DIRECTORY/SIZE=ALL [...]*.MOD`. DCL does not hand
the words to the program to sort out. A **command definition**, written
for the Command Definition Utility in a `.cld` file, says what the verb
takes, and DCL parses the line against it before the program starts: it
checks the qualifiers, applies the defaults, prompts for a missing
parameter, and refuses a line that does not fit, with its own message.
The program then asks for each part by name. VMSLIB's `CommandLanguage`
asks for them, through the `CLI$` routines.

A program can do this in three ways:

- **As a verb of its own**, defined by `SET COMMAND`, which DCL parses
  before it starts.
- **With a table of its own**, compiled from a `.cld` file and linked
  with it, to parse lines it reads itself: a command loop, or a file of
  commands.
- **As a foreign command** that parses its own line with such a table.

A program that wants Unix-style arguments needs none of this:
`Args` and `Modules` give a foreign command's words (chapter 5).

### A verb of your own

`GREET.CLD` defines the verb `GREET`:

<!-- example: vax/greet/Greet.cld -->
```
DEFINE VERB GREET
    IMAGE GREET_IMAGE
    PARAMETER P1, LABEL=NAMES, PROMPT="Whom", VALUE(REQUIRED, LIST)
    QUALIFIER TIMES, VALUE(REQUIRED, TYPE=$NUMBER)
    QUALIFIER EXCLAIM, DEFAULT
```

- `IMAGE` names the program to run, here by a logical name, so that the
  table need not say where the program is.
- `P1`, the first parameter, has the label `NAMES`, by which the program
  asks for it. It is required, and DCL prompts `Whom` for it at a
  terminal when it is missing. `LIST` lets it be several values separated
  by commas.
- `/TIMES` must have a value, and DCL checks that the value is a number.
- `/EXCLAIM` is present by `DEFAULT`, so it is on unless the command
  says `/NOEXCLAIM`. Every qualifier can be negated so unless its
  definition says `NONEGATABLE`.

The program asks for what DCL parsed:

<!-- example: vax/greet/Greet.Mod -->
```
MODULE Greet;
  IMPORT SYSTEM, Out, CommandLanguage;

  VAR
    name, count: ARRAY 64 OF CHAR;
    status: SYSTEM.INT32;
    times, i: INTEGER;
    ending: CHAR;

  PROCEDURE Number(text: ARRAY OF CHAR): INTEGER;
    VAR n, i: INTEGER;
  BEGIN
    n := 0; i := 0;
    WHILE (text[i] >= "0") & (text[i] <= "9") DO
      n := n * 10 + ORD(text[i]) - ORD("0"); INC(i)
    END;
    RETURN n
  END Number;

BEGIN
  times := 1;
  IF CommandLanguage.IsPresent("TIMES") THEN
    status := CommandLanguage.GetValue("TIMES", count);
    times := Number(count)
  END;
  IF CommandLanguage.IsPresent("EXCLAIM") THEN ending := "!" ELSE ending := "." END;
  REPEAT
    status := CommandLanguage.GetValue("NAMES", name);
    IF status # CommandLanguage.Absent THEN
      FOR i := 1 TO times DO
        Out.String("Hello, "); Out.String(name); Out.Char(ending); Out.Ln
      END
    END
  UNTIL status = CommandLanguage.Absent
END Greet.
```

It is built as any program is. `SET COMMAND` adds the verb to the
process's command table, and the logical name tells DCL where the image
is:

<!-- vax-session: greet -->

    $ POC GREET.MOD
    $ @GREET
    $ DEFINE GREET_IMAGE DISK$USER:[ME.WORK]GREET.EXE
    $ SET COMMAND GREET.CLD
    $ GREET world
    Hello, WORLD!
    $ GREET/TIMES=2/NOEXCLAIM world,"Dear Reader"
    Hello, WORLD.
    Hello, WORLD.
    Hello, Dear Reader.
    Hello, Dear Reader.
    $ GREET/TIMES=many world
    %DCL-W-NUMBER, invalid numeric value - supply an integer
     \MANY\
    $ GREET/LOUD world
    %DCL-W-IVQUAL, unrecognized qualifier - check validity, spelling, and placement
     \LOUD\

The last two never start the program: DCL refuses the line itself. As
DCL does with every command, it makes the text outside quotes uppercase.
`SET COMMAND` lasts for the process, so a user who wants the verb always
puts it in `LOGIN.COM`. A system manager can add it to the system's DCL
tables for everyone.

### Asking about the line

`CommandLanguage` names a parameter or qualifier by its label, or by its
name when it has none (`P1`, `TIMES`). A keyword of a qualifier's value is
named after a period, `STYLE.FULL`.

`Presence(entity)` says how the entity is on the line:

| Result | Means |
|---|---|
| `Present` | On the line. |
| `Negated` | On the line with `NO`: `/NOEXCLAIM`. |
| `Defaulted` | Not on the line, but present by `DEFAULT`. |
| `LocallyPresent`, `LocallyNegated` | A positional qualifier, after a parameter value rather than the verb. |
| `Absent` | None of these. |

`IsPresent` is `TRUE` for `Present`, `LocallyPresent` and `Defaulted`.

`GetValue(entity, value)` gives the entity's next value each time it is
called. Its result says what follows the value: `More` for a comma,
`Concatenated` for a plus sign, `Last` for nothing. After the last value
it returns `Absent`, with `value` empty, so a loop asks until `Absent`,
as `Greet` does. A value too long for `value` is cut short, and the
result is `Truncated`.

Two entities are DCL's own. `$VERB` is the verb's first four letters,
which `GetVerb` gives, and `$LINE` is the whole line as DCL keeps it,
which `GetLine` gives.

A program run as a verb still has `Args` and `Modules`. Their arguments
are the words of DCL's copy of the line after the verb, as `GetLine`
shows it: uppercase except quoted text, with the quotes gone.

### A table of your own

A program that reads commands itself, from a terminal or a file,
parses each line with its own table. The `.cld` file has a `MODULE`
statement, which names the table:

<!-- example: vax/shell/ShellCommands.cld -->
```
MODULE SHELL_COMMANDS
DEFINE VERB GREET
    PARAMETER P1, LABEL=NAME, PROMPT="Whom", VALUE(REQUIRED)
    QUALIFIER EXCLAIM, DEFAULT
DEFINE VERB COUNT
DEFINE VERB EXIT
```

A verb in a table of its own needs no `IMAGE` or `ROUTINE` clause. The
program finds out which verb it has from `GetVerb`, by the verb's first
four letters, which are unique in a table.

The table is data, at the address of a global symbol, `SHELL_COMMANDS`.
Oberon cannot name an external variable, so the program declares the
symbol as an external procedure, never called, and passes its address:

<!-- example: vax/shell/Shell.Mod -->
```
MODULE Shell;
  IMPORT SYSTEM, Out, CommandLanguage;

  VAR
    table: SYSTEM.ADDRESS;
    status: SYSTEM.INT32;
    verb: ARRAY 8 OF CHAR;
    name: ARRAY 64 OF CHAR;
    greetings: INTEGER;

  (* the table's global symbol, named by ShellCommands.cld's MODULE *)
  PROCEDURE ["VMS", "SHELL_COMMANDS"] Commands;

BEGIN
  table := SYSTEM.VAL(SYSTEM.ADDRESS, Commands);
  greetings := 0;
  REPEAT
    status := CommandLanguage.ParsePrompting("SHELL> ", table);
    verb := "";
    IF status = CommandLanguage.Parsed THEN
      CommandLanguage.GetVerb(verb);
      IF verb = "GREE" THEN
        status := CommandLanguage.GetValue("NAME", name);
        Out.String("Hello, "); Out.String(name);
        IF CommandLanguage.IsPresent("EXCLAIM") THEN Out.Char("!") ELSE Out.Char(".") END;
        Out.Ln;
        INC(greetings)
      ELSIF verb = "COUN" THEN
        Out.Int(greetings, 0); Out.String(" greeted"); Out.Ln
      END
    END
  UNTIL (status = CommandLanguage.EndOfInput) OR (verb = "EXIT")
END Shell.
```

Give poc the `.cld` file after the program, and the procedure poc writes
compiles the table with `SET COMMAND/OBJECT` and links it in. The `.cld`
file must not have the same name as one of the program's modules, since
each becomes an object file of that name.

    $ POC SHELL.MOD SHELLCOMMANDS.CLD
    $ @SHELL

`ParsePrompting` reads a line from `SYS$INPUT`, prompting `SHELL> ` at a
terminal, and parses it. Here it reads the lines of a command procedure:

    $ RUN SHELL
    greet world
    greet/noexclaim "Dear Reader"
    count
    exit

prints

<!-- vax-session: shell -->

    Hello, WORLD!
    Hello, Dear Reader.
    2 greeted

For a line that does not fit, such as `frob`, DCL prints its message,
`%CLI-W-IVVERB` here, and, since the program has no condition handler, a
traceback (chapter 13). The procedure returns the status as well, so the
loop goes on. At a terminal,
`ParsePrompting` prompts for a missing parameter with its `PROMPT` text,
and a line ending with a hyphen is continued on the next. CTRL/Z, or an
empty line, returns `EndOfInput`.

`Parse(line, table)` parses a line the program already has, of at most
256 characters. It does not prompt, and returns `MissingParameter` for a
missing parameter.

| What a Parse procedure returns | When |
|---|---|
| `Parsed` | The line fits the table. |
| `UnknownVerb`, `UnknownQualifier`, `MissingParameter` | It does not. DCL has printed its message too. |
| `NoCommand` | The line is empty. |
| `EndOfInput` | CTRL/Z or an empty line at `ParsePrompting`'s prompt. |
| `NoTable` | The table's address is 0. |
| `InvalidRequest` | The process has no command interpreter. |

After a Parse procedure, `RestoreParse` brings back DCL's parse of the
command that ran the program.

### A foreign command with qualifiers

A program run as a foreign command (`GREET :== $DISK$USER:[ME]GREET.EXE`)
has no parse until it makes one, and asking `Presence` or `GetValue`
about an entity the running command's verb does not have stops the
program (`%CLI-F-SYNTAX`). `ParseForeign(verb, table)` parses the
program's own command line as if `verb` came before it, so its
qualifiers work too. A program that may be run both ways tests
`GetVerb` first: under its own verb DCL has already parsed the line.

### Without a command interpreter

The `CLI$` routines need DCL. A detached process, started by `RUN
/DETACHED` without a command interpreter, has none, and every procedure
of `CommandLanguage` returns `InvalidRequest` there. `HasInterpreter`
tells a program before it asks.

## 11. Records RMS keeps

*For the Unix reader: files that hold records, which VMS can find by key
or by number. For the VMS reader: RMS's services from Oberon.*

Every VMS file is kept by RMS, the Record Management Services, and has
an **organization**:

- **Sequential**: records one after another, read and written in order.
  Text files are sequential, and `Files` reads and writes them (chapter
  5), so a program needs nothing more for them.
- **Relative**: numbered cells of one size, each empty or holding a
  record, read and written by number, as an array on disk.
- **Indexed**: records kept in the order of a **key**, a field of each
  record, and found by its value, as in a small database. A file can
  have several keys, each with its own order.

`Files` is made for sequential files, and knows nothing of record
numbers or keys. A program uses RMS's services for relative and indexed
files, from VMSDEF (chapter 9).

### RMS's blocks

A program describes what it wants in **control blocks**, records RMS
reads and writes, and passes them to the services:

- **A FAB**, `FABDEF.FABDEF`, describes a file: its name, organization,
  record format and size, and what the program will do with it.
- **A RAB**, `RABDEF.RABDEF`, describes a **stream** of record operations
  on an open file: where records come from and go to, and how the next
  one is found.
- **XABs** add attributes. An `XABKEYDEF.XABKEYDEF` describes a key of an
  indexed file being created.

MACRO-32 programs make them with the `$FAB`, `$RAB` and `$XABKEY`
macros. An Oberon program does what the macros do:

- **Each block's identifier and length** are set first:
  `FAB$B_BID := FABDEF.FAB$C_BID` and `FAB$B_BLN := FABDEF.FAB$C_BLN`. An
  XAB's, which its record has no fields for, are set by `SYSTEM.PUT` at
  `XABDEF`'s offsets, as `SetKey` below does.
- **An address is a `SYSTEM.CARD32`**, the address of the name, the
  buffer, the next block. RMS keeps these addresses from one call to the
  next, so the blocks and what they point to are global variables, or on
  the heap, never a procedure's local variables.
- **A file name is an address and a length** (`FAB$L_FNA` and
  `FAB$B_FNS`), not a string descriptor.
- **Every service returns a condition value**, `RMS$_NORMAL` or another
  `RMS$_` code of `RMSDEF`, and leaves it in the block's `STS` field too.
  `Conditions.Message` gives its text.

### An indexed file

This program creates an indexed file of parts, whose records hold a
part's number (key 0), where it is kept (key 1), and what it is. It adds
records, lists them by each key, finds some, and moves one part:

<!-- example: vax/parts/Parts.Mod -->
```
MODULE Parts;
  IMPORT SYSTEM, Out, Conditions, STARLET, FABDEF, RABDEF, XABDEF, XABKEYDEF;

  CONST
    (* a record: a part's number, the place it is kept, and what it is *)
    numberSize = 6; placeSize = 8; recordSize = 32;

  TYPE Record = ARRAY recordSize OF CHAR;

  VAR (* global, since RMS keeps their addresses *)
    name: ARRAY 16 OF CHAR;
    file: FABDEF.FABDEF;
    stream: RABDEF.RABDEF;
    byNumber, byPlace: XABKEYDEF.XABKEYDEF;
    record: Record;
    key: ARRAY numberSize OF CHAR;
    status: SYSTEM.INT32;
    found: BOOLEAN; (* whether the last Get found a record *)

  (* x's address, as RMS's blocks hold it *)
  PROCEDURE Address(VAR x: ARRAY OF SYSTEM.BYTE): SYSTEM.CARD32;
  BEGIN
    RETURN SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(x))
  END Address;

  (* RMS's message for status, if it is not a success *)
  PROCEDURE Check(what: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 100 OF CHAR;
  BEGIN
    IF ~ODD(status) THEN
      Conditions.Message(status, text);
      Out.String(what); Out.String(": "); Out.String(text); Out.Ln
    END
  END Check;

  (* s into record from at, padded with blanks to size *)
  PROCEDURE Fill(at, size: INTEGER; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < size) & (s[i] # 0X) DO record[at + i] := s[i]; INC(i) END;
    WHILE i < size DO record[at + i] := " "; INC(i) END
  END Fill;

  (* record, less its trailing blanks *)
  PROCEDURE Print;
    VAR i, n: INTEGER;
  BEGIN
    n := recordSize;
    WHILE (n > 0) & (record[n - 1] = " ") DO DEC(n) END;
    Out.String("  ");
    FOR i := 0 TO n - 1 DO Out.Char(record[i]) END;
    Out.Ln
  END Print;

  (* a key of reference, at position, of size characters; next the
     address of the next key's block, or 0 *)
  PROCEDURE SetKey(VAR k: XABKEYDEF.XABKEYDEF; reference: SYSTEM.CARD8;
                   position: SYSTEM.CARD16; size, flags: SYSTEM.CARD8; next: SYSTEM.CARD32);
  BEGIN
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$B_COD, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEY));
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$B_BLN, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEYLEN));
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$L_NXT, next);
    k.XAB$B_REF := reference; k.XAB$B_DTP := XABKEYDEF.XAB$C_STG;
    k.XAB$W_POS[0] := position; k.XAB$B_SIZ[0] := size; k.XAB$B_FLG := flags
  END SetKey;

  PROCEDURE Add(number, place, description: ARRAY OF CHAR);
  BEGIN
    Fill(0, numberSize, number); Fill(numberSize, placeSize, place);
    Fill(numberSize + placeSize, recordSize - numberSize - placeSize, description);
    stream.RAB$B_RAC := RABDEF.RAB$C_KEY;
    Check(number, STARLET.SYS$PUT(stream, NIL, NIL))
  END Add;

  (* every record, in the order of key reference *)
  PROCEDURE List(what: ARRAY OF CHAR; reference: SYSTEM.CARD8);
    VAR status: SYSTEM.INT32;
  BEGIN
    Out.String(what); Out.Ln;
    stream.RAB$B_KRF := reference;
    Check("rewind", STARLET.SYS$REWIND(stream, NIL, NIL));
    stream.RAB$B_RAC := RABDEF.RAB$C_SEQ;
    status := STARLET.SYS$GET(stream, NIL, NIL);
    WHILE ODD(status) DO
      Print; status := STARLET.SYS$GET(stream, NIL, NIL)
    END
  END List;

  (* the first record whose number starts with the first size
     characters of number, if there is one: found *)
  PROCEDURE Get(number: ARRAY OF CHAR; size: SYSTEM.CARD8);
    VAR i: INTEGER; status: SYSTEM.INT32;
  BEGIN
    FOR i := 0 TO numberSize - 1 DO key[i] := " " END;
    i := 0; WHILE number[i] # 0X DO key[i] := number[i]; INC(i) END;
    stream.RAB$B_RAC := RABDEF.RAB$C_KEY; stream.RAB$B_KRF := 0;
    stream.RAB$L_KBF := Address(key); stream.RAB$B_KSZ := size;
    status := STARLET.SYS$GET(stream, NIL, NIL);
    Out.String("get "); Out.String(number); Out.Ln;
    Check("  not found", status);
    found := ODD(status);
    IF found THEN Print END
  END Get;

BEGIN
  name := "PARTS.DAT";
  file.FAB$B_BID := FABDEF.FAB$C_BID; file.FAB$B_BLN := FABDEF.FAB$C_BLN;
  file.FAB$L_FNA := Address(name); file.FAB$B_FNS := 9; (* its length *)
  file.FAB$B_FAC := FABDEF.FAB$M_GET + FABDEF.FAB$M_PUT + FABDEF.FAB$M_UPD;
  file.FAB$B_ORG := FABDEF.FAB$C_IDX; file.FAB$B_RFM := FABDEF.FAB$C_FIX;
  file.FAB$W_MRS := recordSize; file.FAB$L_XAB := Address(byNumber);
  SetKey(byNumber, 0, 0, numberSize, 0, Address(byPlace));
  SetKey(byPlace, 1, numberSize, placeSize, XABKEYDEF.XAB$M_DUP + XABKEYDEF.XAB$M_CHG, 0);
  status := STARLET.SYS$CREATE(file, NIL, NIL); Check("create", status);
  IF ODD(status) THEN
    stream.RAB$B_BID := RABDEF.RAB$C_BID; stream.RAB$B_BLN := RABDEF.RAB$C_BLN;
    stream.RAB$L_FAB := Address(file);
    stream.RAB$L_UBF := Address(record); stream.RAB$W_USZ := recordSize;
    stream.RAB$L_RBF := Address(record); stream.RAB$W_RSZ := recordSize;
    Check("connect", STARLET.SYS$CONNECT(stream, NIL, NIL));

    Add("P300", "SHELF-B", "hinge");
    Add("P100", "SHELF-A", "bolt");
    Add("P500", "BIN-7", "washer");
    Add("P200", "SHELF-B", "nut");
    Add("P310", "SHELF-A", "hinge pin");
    Add("P200", "BIN-1", "a second P200");
    List("by number", 0);
    List("by place", 1);

    Get("P300", numberSize); Get("P400", numberSize); Get("P3", 2);
    Get("P100", numberSize);
    IF found THEN
      Fill(numberSize, placeSize, "BIN-1");
      Check("update", STARLET.SYS$UPDATE(stream, NIL, NIL))
    END;
    List("by place", 1);

    file.FAB$L_FOP := FABDEF.FAB$M_DLT; (* delete the file when it is closed *)
    Check("close", STARLET.SYS$CLOSE(file, NIL, NIL))
  END
END Parts.
```

<!-- vax-session: parts -->

    $ RUN PARTS
    P200: %RMS-F-DUP, duplicate key detected (DUP not set)
    by number
      P100  SHELF-A bolt
      P200  SHELF-B nut
      P300  SHELF-B hinge
      P310  SHELF-A hinge pin
      P500  BIN-7   washer
    by place
      P500  BIN-7   washer
      P100  SHELF-A bolt
      P310  SHELF-A hinge pin
      P300  SHELF-B hinge
      P200  SHELF-B nut
    get P300
      P300  SHELF-B hinge
    get P400
      not found: %RMS-E-RNF, record not found
    get P3
      P300  SHELF-B hinge
    get P100
      P100  SHELF-A bolt
    by place
      P100  BIN-1   bolt
      P500  BIN-7   washer
      P310  SHELF-A hinge pin
      P300  SHELF-B hinge
      P200  SHELF-B nut

What the program does, step by step:

- **`$CREATE`** makes the file from the FAB: organization
  `FAB$C_IDX`, fixed-length records (`FAB$C_FIX`) of `FAB$W_MRS`
  characters, and its keys, from the XABs chained from `FAB$L_XAB`. Key 0,
  the primary key, may not have duplicates, so the second `P200` is
  refused. Key 1 allows them (`XAB$M_DUP`) and allows an update to change
  it (`XAB$M_CHG`). `FAB$B_FAC` says what the program will do: get, put
  and update records.
- **`$CONNECT`** makes the RAB a stream on the open file. The RAB's
  `UBF` and `USZ` are the buffer a `$GET` reads into, `RBF` and `RSZ` the
  record a `$PUT` or `$UPDATE` writes.
- **`$PUT`** adds the record, which goes in each key's order wherever
  it belongs.
- **`$REWIND`** and sequential **`$GET`s** (`RAB$C_SEQ`) read the records
  in the order of key `RAB$B_KRF`. Records with the same key come in the
  order they were put. The last `$GET` returns `RMS$_EOF`.
- **A keyed `$GET`** (`RAB$C_KEY`) finds the first record whose key
  starts with the `RAB$B_KSZ` characters at `RAB$L_KBF`: all of the key
  for an exact match, fewer for a generic one, as `P3` finds `P300`.
  `RAB$M_KGE` in `RAB$L_ROP` finds the first key greater than or equal
  instead. A key is compared with the record's bytes, so it is padded as
  the record is: `P400` with two blanks.
- **`$UPDATE`** rewrites the record the stream last found, and moves it
  in the order of each key that changed. `$DELETE` would delete it.
  `$FIND` finds a record as `$GET` does, without reading it, for an
  update or a delete.
- **`$CLOSE`** closes the file. `FAB$M_DLT` in `FAB$L_FOP` deletes it as
  it closes, so that the example leaves nothing behind.

### A relative file

A relative file is made with organization `FAB$C_REL`. A keyed operation
on it takes a record number, a longword, as its key:

    slots.FAB$B_ORG := FABDEF.FAB$C_REL;
    slots.FAB$B_RFM := FABDEF.FAB$C_FIX;
    slots.FAB$W_MRS := slotSize;
    ...
    slotStream.RAB$B_RAC := RABDEF.RAB$C_KEY;
    slotStream.RAB$L_KBF := Address(number);
    slotStream.RAB$B_KSZ := 4;

With `number` set to 4, a `$PUT` writes cell 4, and a `$GET` reads it. A
`$GET` of a cell never written returns `RMS$_RNF`. A sequential `$GET`
skips the empty cells.

### Sharing a file

`FAB$B_SHR` says what other streams may do with a file while this one
has it open: `FAB$M_SHRGET`, `SHRPUT`, `SHRUPD` and `SHRDEL`, added
together. Without them, another `$OPEN` of the file fails. With them,
each stream locks the record it last read, and another stream's `$GET`
of that record returns `RMS$_RLK`, "record locked", until the first
stream goes on to another record or releases it with `$RELEASE`. A
program that shares a file must be ready for `RMS$_RLK`, and try again.

### Files made by DCL

A file need not be made by the program that uses it. `CREATE/FDL` makes
a file from a description in the File Definition Language, which `EDIT
/FDL` writes, keys included. A program then opens it with `$OPEN`, which
needs no XABs, since RMS reads the keys from the file. `DIRECTORY/FULL`
shows a file's organization and record format, and `ANALYZE/RMS_FILE`
its keys and structure.

## 12. Screens

*For the Unix reader: escape sequences work as they do on Unix, and VMS
has a screen library of its own, much as curses is. For the VMS reader:
`SMG$` from Oberon.*

A program draws on a terminal's screen in one of two ways: with `VT100`,
the escape sequences of the runtime's module, as on Unix, or with VMS's
Screen Management routines, `SMG$`, which know every terminal type VMS
knows and keep track of what is on the screen.

### `VT100`

`VT100` is the module the *User's Guide* describes, with the same
procedures and constants: `CUP` moves the cursor, `ED` erases the
display, `SetAttr` sets a rendition, and so on. On VMS, each procedure
calls `Out.Flush` after its sequence. `Out` keeps a line until `Ln`
there, and `Flush` writes what it holds to a terminal without ending the
line, so a sequence reaches the screen when it is sent, after the text
written before it. To a file `Flush` does nothing, and the file gets the
sequences in the lines they were written in.

    VT100.ED(2); VT100.CUP(1, 1);
    VT100.SetAttr(VT100.Bold); Out.String("Peaseblossom");
    VT100.SetAttr(VT100.ResetAll); Out.Ln

VMS's terminal driver passes the sequences to the terminal as they are,
so this works on a VT100 or any later DEC terminal, and on any emulator
of one.

### `SMG$`

The Screen Management routines draw on a terminal through objects of
their own, each named by a longword identifier that the program keeps:

- **A pasteboard** is a screen, the terminal's or a file's.
- **A virtual display** is a rectangle of text, with an optional
  border and a label on it. A program writes into a display, and pastes
  it onto a pasteboard at a row and column. Displays can overlap, be
  moved and be unpasted, and SMG redraws what changes.
- **A virtual keyboard** reads keys and lines, the terminal's or a
  file's.

They are reached through VMSDEF's `SMG_ROUTINES`, with `SMGDEF`'s
constants and `SMGMSG`'s condition values. VMSLIB has no module over
them. An argument SMG takes by reference may be any expression, a string
included, since the generated parameters are read-only, and `NIL` omits
an optional one.

This program draws a bordered display with a label, and text in three
renditions. On the terminal it waits for a key, and given a file name
it draws there instead:

<!-- example: vax/panel/Panel.Mod -->
```
MODULE Panel;
  IMPORT SYSTEM, Out, Args, SMGDEF, SMG_ROUTINES;

  VAR
    pasteboard, keyboard, panel: SYSTEM.CARD32;
    device: ARRAY 64 OF CHAR;
    key: SYSTEM.CARD16;
    failed: SYSTEM.INT32;
    step: ARRAY 32 OF CHAR;

  (* the first step that fails, and its status, kept to print at the end *)
  PROCEDURE Check(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    IF ~ODD(status) & (failed = 0) THEN failed := status; COPY(what, step) END
  END Check;

BEGIN
  Args.Get(1, device); (* the file to draw into; the terminal if none *)
  IF device = "" THEN
    Check("create pasteboard", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(pasteboard, NIL, NIL, NIL, NIL, NIL))
  ELSE
    Check("create pasteboard", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(pasteboard, device, NIL, NIL, NIL, NIL))
  END;
  Check("create display", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(4, 30, panel,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Check("label", SMG_ROUTINES.SMG$LABEL_BORDER(panel, " Peaseblossom ", SMGDEF.SMG$K_TOP,
    NIL, NIL, NIL, NIL));
  Check("put", SMG_ROUTINES.SMG$PUT_CHARS(panel, "an Oberon-2 compiler", 1, 2, NIL, NIL, NIL, NIL));
  Check("put", SMG_ROUTINES.SMG$PUT_CHARS(panel, "for VAX/VMS 5.5-2", 2, 2, NIL,
    SMGDEF.SMG$M_BOLD, NIL, NIL));
  Check("put", SMG_ROUTINES.SMG$PUT_CHARS(panel, "Press any key", 4, 2, NIL,
    SMGDEF.SMG$M_REVERSE, NIL, NIL));
  Check("paste", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(panel, pasteboard, 2, 3, NIL));
  IF device = "" THEN
    Check("create keyboard", SMG_ROUTINES.SMG$CREATE_VIRTUAL_KEYBOARD(keyboard, NIL, NIL, NIL, NIL));
    Check("read keystroke", SMG_ROUTINES.SMG$READ_KEYSTROKE(keyboard, key, NIL, NIL, NIL, NIL, NIL));
    Check("delete keyboard", SMG_ROUTINES.SMG$DELETE_VIRTUAL_KEYBOARD(keyboard))
  ELSE
    Check("snapshot", SMG_ROUTINES.SMG$SNAPSHOT(pasteboard, NIL))
  END;
  Check("delete pasteboard", SMG_ROUTINES.SMG$DELETE_PASTEBOARD(pasteboard, NIL));
  IF failed # 0 THEN
    Out.String(step); Out.String(" failed: %X"); Out.Hex(failed, 8); Out.Ln
  END
END Panel.
```

On a terminal the display appears at the top left, with "for VAX/VMS
5.5-2" in bold and "Press any key" in reverse video. A key clears the screen, since
deleting the pasteboard does. Run as a foreign command with a file name,
it draws into the file:

<!-- vax-session: panel -->

    $ PANEL := $'F$ENVIRONMENT("DEFAULT")'PANEL
    $ PANEL PANEL.LIS
    $ SEARCH PANEL.LIS "|","+"
     +-------- Peaseblossom --------+
     | an Oberon-2 compiler         |
     | for VAX/VMS 5.5-2            |
     |                              |
     | Press any key                |
     +------------------------------+

A file is not a terminal, so the border is drawn with `+`, `-` and `|`,
and the renditions do not show. (On a VT100 the bytes logged showed the
same displays in bold and reverse video, and the screen cleared at the
end.) A pasteboard on a file is written only
by `SMG$SNAPSHOT`, which writes the whole screen as it is then, 66 lines
of 132 columns, each without its trailing blanks. `SEARCH` here shows
just the lines with the display on them.

### Keys and menus

`SMG$READ_STRING` reads a line, with a prompt, into a string, and
`SMG$READ_KEYSTROKE` one key, as a code: a character's own code, or one
of `SMGDEF`'s `SMG$K_TRM_` codes for a function key, such as
`SMG$K_TRM_PF1` or `SMG$K_TRM_UP`. `SMG$KEYCODE_TO_NAME` names it.

A menu is a display that `SMG$CREATE_MENU` fills with choices, and
`SMG$SELECT_FROM_MENU` lets the user move among them with the arrow keys
and pick one with Return. The choices are an array of fixed-length
strings, passed as a `CLASS_A` descriptor by its address:

    VAR choices: ARRAY 4 OF ARRAY 10 OF CHAR;
        descriptor: VmsArguments.ArrayDescriptor;
    ...
    VmsArguments.DescribeArray(descriptor, choices);
    status := SMG_ROUTINES.SMG$CREATE_MENU(menu, SYSTEM.ADR(descriptor),
      SMGDEF.SMG$K_VERTICAL, NIL, NIL, NIL, NIL);

Each choice is padded with blanks to its length, not ended by `0X`,
which SMG would show. A menu is chosen only on a terminal: on a keyboard
that reads a file, `SMG$SELECT_FROM_MENU` returns `SMG$_EOF`.

### Rules for a program that uses `SMG$`

- **Write nothing with `Out` while a pasteboard is on the terminal.**
  SMG does not know of `Out`'s lines, which would come between its own
  and spoil the screen. Print after deleting the pasteboard instead.
- **Delete the pasteboard before the program ends**, or the terminal
  is left as SMG set it. Deleting it clears the screen unless the flags
  say otherwise.
- **Check each status.** Most `SMG$` routines return one rather than
  signal, so a mistake goes unseen unless the program looks, as `Check`
  does above.

## 13. Conditions and handlers

*For the Unix reader: VMS's way of reporting errors, which works more
like an exception than like a returned error code. For the VMS reader:
condition handlers in Oberon.*

Most VMS routines return a condition value (chapter 7). Some **signal**
one instead: they hand it to VMS, which looks for a handler to deal with
it, as an exception is thrown. Most of `STR$` and `MTH$` signal their
errors. So do `LIB$SIGNAL` and `LIB$STOP`, which a program calls to
signal a condition itself. The hardware signals too, for an access
violation, a division by zero or a real overflow.

### When nothing handles a signal

A poc program establishes no handler of its own, so a signal reaches VMS's
last one. It prints the condition's message and a traceback of the calls
that led to it, to `SYS$OUTPUT` and to `SYS$ERROR`. Then:

- **For a warning, a success, an informational condition or an error**,
  the program goes on after the call that signalled.
- **For a severe (fatal) condition**, the program ends, with that
  condition as its status. `LIB$STOP` always makes its condition severe,
  and so a stop always ends the program.

A real overflow, in chapter 5, is a severe hardware condition, and ends
the program so.

### Signalling a condition

`Conditions` signals with `Signal`, or with `SignalWith` when the
message has one FAO directive, such as `!AS` for a string, which takes a
descriptor's address. With no handler, this prints, before its traceback:

    VmsArguments.Describe(descriptor, image);
    Conditions.SignalWith(LIBDEF.LIB$_ACTIMAGE, SYSTEM.VAL(SYSTEM.INT32, SYSTEM.ADR(descriptor)));

    %LIB-E-ACTIMAGE, error activating image POC_NO_IMAGE

`Stop` and `StopWith` stop. `SignalList` and `StopList` take the whole
list `LIB$SIGNAL` takes, in an array: a condition, the number of its FAO
arguments and the arguments, then optionally another condition with its
own, and so on. Each condition after the first is printed with a `-`, as
the cause of the one before it:

    %LIB-E-ACTIMAGE, error activating image POC_FIRST
    -LIB-E-ACTIMAGE, error activating image POC_SECOND
    -SYSTEM-F-IVLOGNAM, invalid logical name

Nothing checks a list: a wrong one prints a wrong message.

### Handlers

A procedure gives itself a handler with `Conditions.Establish`. A
condition signalled while the procedure runs, in it or in anything it
calls, is offered to its handler. The handlers are tried from the newest
frame outwards, each procedure's in turn, until one deals with the
condition. A handler is removed when its procedure returns, or earlier
by `Conditions.Revert`.

A handler is a global procedure of type `Conditions.Handler`:

    PROCEDURE (VAR signal: Conditions.SignalArray;
               VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;

`signal[1]` is the condition, `signal[0]` the number of longwords after
`signal[0]`, the last two of them being the PC and PSL where the
condition was signalled, and the FAO arguments between. `mechanism[2]` is
how many frames out from the signal the handler's own procedure is, and
`mechanism[3]` the value its procedure returns if the handler unwinds.
The handler then does one of three things:

- **Returns `Conditions.Continue`**: the program goes on after the call
  that signalled, as if the signal had returned. A severe condition
  cannot be continued, and ends the program.
- **Returns `Conditions.Resignal`**: the condition is offered to the next
  handler out, and finally to VMS's.
- **Calls `Conditions.Unwind` and returns**: the handler's own procedure
  returns to its caller at once, with `mechanism[3]` as its result, and
  every frame between it and the signal is removed.

This handler notes each warning and continues, and offers any other
condition further out:

<!-- example: vax/warnings/Warnings.Mod -->
```
MODULE Warnings;
  IMPORT SYSTEM, Out, Conditions, SSDEF;

  VAR warnings: INTEGER;

  (* a warning noted and continued; anything else offered further out *)
  PROCEDURE NoteWarnings(VAR signal: Conditions.SignalArray;
                         VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
    VAR text: ARRAY 100 OF CHAR;
  BEGIN
    IF Conditions.Severity(signal[1]) # Conditions.Warning THEN
      RETURN Conditions.Resignal
    END;
    INC(warnings);
    Conditions.Message(signal[1], text);
    Out.String("noted: "); Out.String(text); Out.Ln;
    RETURN Conditions.Continue
  END NoteWarnings;

  PROCEDURE Work;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(NoteWarnings);
    Conditions.Signal(SSDEF.SS$_ENDOFFILE);
    Conditions.Signal(SSDEF.SS$_NOSUCHFILE);
    Out.String("the work goes on"); Out.Ln
  END Work;

BEGIN
  Work;
  Out.Int(warnings, 0); Out.String(" warnings"); Out.Ln
END Warnings.
```

<!-- vax-session: warnings -->

    $ RUN WARNINGS
    noted: %SYSTEM-W-ENDOFFILE, end of file
    noted: %SYSTEM-W-NOSUCHFILE, no such file
    the work goes on
    2 warnings

No message or traceback is printed for either warning: the handler dealt
with them. `Conditions.Message` gives a message's text as VMS writes it,
with its FAO directives left as they are.

A handler that unwinds turns a signal into a result. `Readable` here
tries to read an address. An access violation, a hardware condition, is
signalled to its handler, which makes `Readable` return 0, `FALSE`:

<!-- example: vax/probe/Probe.Mod -->
```
MODULE Probe;
  IMPORT SYSTEM, Out, Conditions, SSDEF;

  VAR global: INTEGER;

  (* an access violation ends Readable, which returns FALSE *)
  PROCEDURE AccessHandler(VAR signal: Conditions.SignalArray;
                          VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
    VAR status: SYSTEM.INT32;
  BEGIN
    IF signal[1] # SSDEF.SS$_ACCVIO THEN RETURN Conditions.Resignal END;
    mechanism[3] := 0; (* what Readable returns *)
    status := Conditions.Unwind();
    RETURN Conditions.Continue
  END AccessHandler;

  (* whether the longword at address can be read *)
  PROCEDURE Readable(address: SYSTEM.ADDRESS): BOOLEAN;
    VAR previous: Conditions.Handler; value: SYSTEM.INT32;
  BEGIN
    previous := Conditions.Establish(AccessHandler);
    SYSTEM.GET(address, value);
    RETURN TRUE
  END Readable;

  PROCEDURE Show(what: ARRAY OF CHAR; address: SYSTEM.ADDRESS);
  BEGIN
    Out.String(what); Out.String(" readable: ");
    IF Readable(address) THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END Show;

BEGIN
  Show("address 0", 0);
  Show("a variable", SYSTEM.ADR(global))
END Probe.
```

<!-- vax-session: probe -->

    $ RUN PROBE
    address 0 readable: no
    a variable readable: yes

While an unwind removes the frames, VMS calls each of their handlers
once more, with the condition `Conditions.Unwinding`, so that a
procedure being left can clean up. Such a handler returns, and its
answer does not matter. `DecimalStrings` uses VMS's own handler
`LIB$SIG_TO_RET` in the same way, to turn `STR$`'s signals into returned
statuses.

Three rules follow from how VMS calls a handler:

- **A handler is global.** It cannot be a nested procedure, so it cannot
  see its establisher's local variables. What the two share goes in
  global variables, or in `mechanism[3]` for a result.
- **A handler sees conditions from everything its procedure calls**,
  library routines and the runtime included. One that continues every
  condition it is given hides errors it did not expect, so a handler
  should resignal what it does not know, as both examples do.
- **At AST level, a handler must not unwind.** A condition signalled in
  an AST routine is also offered to the handlers of the frames that the
  AST interrupted. Unwinding one of those would remove frames of code
  that is not running. A handler tests `AsynchronousTraps.InProgress`
  first (chapter 14).

### Exit handlers

An exit handler is called when the program ends, however it ends:
normally, by `$EXIT` or `HALT`, by a trap or by a severe condition.
`ExitHandlers.Declare` declares one. The handler is given the exit
status:

<!-- example: vax/goodbye/Goodbye.Mod -->
```
MODULE Goodbye;
  IMPORT SYSTEM, Out, ExitHandlers;

  VAR status: SYSTEM.INT32;

  PROCEDURE AtExit(VAR exitStatus: SYSTEM.CARD32);
  BEGIN
    Out.String("exiting with status %X"); Out.CardHex(exitStatus, 8); Out.Ln
  END AtExit;

BEGIN
  status := ExitHandlers.Declare(AtExit);
  Out.String("the program ends by HALT(3)"); Out.Ln;
  HALT(3)
END Goodbye.
```

<!-- vax-session: goodbye -->

    $ RUN GOODBYE
    the program ends by HALT(3)
    exiting with status %X1000001A

`HALT(3)` ends the program with status `%X1000001A`, as chapter 5 says.
Exit handlers run last declared, first called, and each once. poc's own,
which writes `Out`'s last line and runs the finalizers, was declared
first, so it runs after the program's: output from an exit handler still
appears. Changing the status in a handler changes nothing. A handler
that calls `$EXIT` itself ends the program there, with the status it
gives. The handlers not yet called are then skipped, poc's own among
them, so `Out`'s unfinished line is lost and no finalizer runs.

## 14. Asynchronous system traps

*For the Unix reader: VMS's way of telling a program that something has
happened, like a signal handler, but queued and orderly. For the VMS
reader: AST routines in Oberon.*

An **asynchronous system trap** (AST) is a call VMS makes to a routine of
the program's when something it asked for happens: a timer expires, an
I/O request completes, CTRL/C is typed. The program asks for one with the
request, naming the routine and a longword parameter to give it, and goes
on with its work. When the event comes, VMS interrupts the program
wherever it is, calls the routine, and lets the program go on from there
when the routine returns.

### An AST routine

An AST routine is a global procedure of type `AsynchronousTraps.Routine`:

    PROCEDURE (parameter: SYSTEM.CARD32);

The parameter is the one the request gave, so one routine can serve
several requests and tell them apart. Every routine VMSDEF declares with
an AST argument, such as `$QIO`'s, takes a `Routine`, and `NIL` omits it.
These request ASTs:

- **`Timers.After(milliseconds, routine, parameter)`** calls the routine
  after a time, at least 10 milliseconds, the system clock's resolution.
  `Timers.Cancel(parameter)` cancels the requests made with that
  parameter, and their routine is not called.
- **A system service that completes later**, such as `$QIO`, calls one
  when it does.
- **`AsynchronousTraps.Declare(routine, parameter)`** calls one as soon
  as delivery allows, which is at once, before the next statement, unless
  delivery is disabled.
- **`Platform.SetInterruptHandler`** has one called for CTRL/C, below.

### When an AST runs

An AST is delivered whenever the program runs with delivery enabled:
between any two instructions of the main program, and while it waits, in
`EventFlags.Wait` or `Timers.Sleep`, for instance. Then:

- **An AST routine runs to its end** before the main program, or any
  other AST routine, runs again. A second AST that comes meanwhile waits
  its turn. So an AST routine needs no protection from the main program.
- **The main program needs protection from AST routines.** What it shares
  with one can change between any two of its statements. It disables
  delivery around its use of that data:

        wasEnabled := AsynchronousTraps.Disable();
        ... take what the AST routine left ...
        AsynchronousTraps.Restore(wasEnabled)

  An AST that comes meanwhile waits, and `Restore` delivers it. `Disable`
  returns whether delivery was enabled, so a procedure that disables it
  while its caller already has restores what it found, and the caller's
  protection lasts.
- **`AsynchronousTraps.InProgress()`** tells whether the code calling it
  runs at AST level.

A single variable that one side writes and the other only reads, such as
a flag the AST routine sets, needs no protection. An event flag
(`EventFlags`, chapter 8) is often better still: the main program can wait
for it.

### What an AST routine may do

An AST routine interrupts the main program anywhere, possibly in the
middle of a library routine. So at AST level a program may use:

- `NEW` and its own variables;
- system services, and the `LIB$` routines the RTL manual calls
  AST-reentrant;
- `AsynchronousTraps`, `EventFlags.Set`, `Clear` and `IsSet`, and
  `Timers.After` and `Cancel`.

It may not use `Out`, `Err`, `In`, `Files`, `Texts` or `Oberon`, whose
state the main program may be halfway through changing. It must not wait
for something that only another AST can bring, which cannot be delivered
until it returns: `Timers.Sleep` is one of those. Waiting for an I/O
request with `$QIOW` is allowed, since its completion is not an AST. poc
checks none of this.

This program's AST routine notes each tick in a list it makes with
`NEW`, and asks for the next. The main program takes the list under
`Disable`, prints it, and stops after the fifth tick, which sets an event
flag:

<!-- example: vax/ticks/Ticks.Mod -->
```
MODULE Ticks;
  IMPORT SYSTEM, Out, AsynchronousTraps, EventFlags, Timers;

  TYPE
    Tick = POINTER TO TickRecord;
    TickRecord = RECORD number: SYSTEM.CARD32; next: Tick END;

  VAR
    ticks: Tick; (* noted by Arrived, newest first, not yet taken *)
    done: SYSTEM.CARD32; (* the event flag the last tick sets *)

  (* an AST routine: notes its tick, and asks for the next until the fifth *)
  PROCEDURE Arrived(number: SYSTEM.CARD32);
    VAR tick: Tick; status: SYSTEM.INT32;
  BEGIN
    NEW(tick); tick.number := number; tick.next := ticks; ticks := tick;
    IF number < 5 THEN
      status := Timers.After(20, Arrived, number + 1)
    ELSE
      status := EventFlags.Set(done)
    END
  END Arrived;

  (* the ticks Arrived has noted since the last Take, oldest first *)
  PROCEDURE Take(): Tick;
    VAR wasEnabled: BOOLEAN; taken, oldestFirst, next: Tick;
  BEGIN
    wasEnabled := AsynchronousTraps.Disable();
    taken := ticks; ticks := NIL;
    AsynchronousTraps.Restore(wasEnabled);
    oldestFirst := NIL;
    WHILE taken # NIL DO
      next := taken.next; taken.next := oldestFirst; oldestFirst := taken; taken := next
    END;
    RETURN oldestFirst
  END Take;

  PROCEDURE Run;
    VAR status: SYSTEM.INT32; finished: BOOLEAN; tick: Tick;
  BEGIN
    status := EventFlags.Get(done);
    status := EventFlags.Clear(done);
    status := Timers.After(20, Arrived, 1);
    Out.String("ticks:");
    REPEAT
      status := Timers.Sleep(30);
      finished := EventFlags.IsSet(done);
      tick := Take();
      WHILE tick # NIL DO
        Out.Char(" "); Out.Card(tick.number, 0); tick := tick.next
      END
    UNTIL finished;
    Out.Ln;
    status := EventFlags.Free(done)
  END Run;

BEGIN
  Run
END Ticks.
```

<!-- vax-session: ticks -->

    $ RUN TICKS
    ticks: 1 2 3 4 5

The main program may take one tick at a time, or several, depending on
how its sleeps and the ticks fall, but it prints them in order, and it
reads the event flag before it takes the list, so that the last tick is
never left behind. Only the main program prints.

### A completion AST

A system service that completes later, such as `$QIO`, takes an AST
routine and its parameter, and calls the routine when the request is
done. The request's I/O status block is filled in first. This program
queues a read from a mailbox, writes to the mailbox, and waits for the
event flag the read's AST sets:

<!-- example: vax/mailbox/Mailbox.Mod -->
```
MODULE Mailbox;
  IMPORT SYSTEM, Out, EventFlags, STARLET, IODEF, VmsArguments;

  VAR
    channel: SYSTEM.CARD16;
    readStatus: VmsArguments.IOStatusBlock;
    received: ARRAY 64 OF CHAR;
    done: SYSTEM.CARD32; (* the event flag ReadDone sets *)

  (* an AST routine, the read's completion *)
  PROCEDURE ReadDone(parameter: SYSTEM.CARD32);
    VAR status: SYSTEM.INT32;
  BEGIN
    received[readStatus.count] := 0X;
    status := EventFlags.Set(done)
  END ReadDone;

  PROCEDURE Run;
    VAR status: SYSTEM.INT32; writeStatus: VmsArguments.IOStatusBlock;
      message: ARRAY 32 OF CHAR;
  BEGIN
    status := EventFlags.Get(done);
    status := EventFlags.Clear(done);
    status := STARLET.SYS$CREMBX(0, channel, 64, 128, 0, 0, NIL, 0);
    status := STARLET.SYS$QIO(0, channel, IODEF.IO$_READVBLK, readStatus,
      ReadDone, 0, received, LEN(received) - 1, 0, 0, 0, 0);
    Out.String("a read is queued"); Out.Ln;
    message := "sent by mailbox";
    status := STARLET.SYS$QIOW(0, channel, IODEF.IO$_WRITEVBLK + IODEF.IO$M_NOW,
      writeStatus, NIL, 0, message, 15, 0, 0, 0, 0);
    Out.String("wrote "); Out.Card(writeStatus.count, 0); Out.String(" characters"); Out.Ln;
    status := EventFlags.Wait(done);
    Out.String("read "); Out.Card(readStatus.count, 0); Out.String(" characters: ");
    Out.String(received); Out.Ln;
    status := STARLET.SYS$DASSGN(channel);
    status := EventFlags.Free(done)
  END Run;

BEGIN
  Run
END Mailbox.
```

<!-- vax-session: mailbox -->

    $ RUN MAILBOX
    a read is queued
    wrote 15 characters
    read 15 characters: sent by mailbox

`$QIOW` is `$QIO` and a wait for its completion. The read completes
during the write, and its AST runs then, at the latest before `$QIOW`
returns. `$QIO`'s buffer, its `P1`, is passed by reference, since
`received` is a variable (chapter 7), and VMS writes to it.

### `NEW` at AST level

`NEW` is safe at AST level in a program that imports `AsynchronousTraps`,
directly or through `Timers`, `EventFlags` or VMSDEF's modules, as nearly
every program that requests an AST does. Its initializer has the heap
disable delivery while it works, so that an AST never finds it halfway
through a change. Without that, an AST routine's `NEW` that interrupts
the heap ends the program by trap 15, with status `%X1000007A`:

    heap re-entered at AST level: import AsynchronousTraps

One that does not interrupt the heap works, but only by luck. The one way
to have an AST without importing `AsynchronousTraps` is a CTRL/C handler.

### CTRL/C

`Platform.SetInterruptHandler` installs a handler for CTRL/C typed at the
terminal `SYS$COMMAND` names. VMS calls it as an AST, with 2, Unix's
`SIGINT`, as its argument, so the rules above apply to it:

    MODULE Patient;
      IMPORT SYSTEM, Platform, AsynchronousTraps;
      VAR interrupted: BOOLEAN;

      PROCEDURE Interrupt(signal: SYSTEM.INT32);
      BEGIN
        interrupted := TRUE
      END Interrupt;
      ...
      Platform.SetInterruptHandler(Interrupt);
      WHILE ~interrupted & (work to do) DO ... END

While a handler is set, CTRL/C no longer stops the program; CTRL/Y
still interrupts it. `SetInterruptHandler(NIL)` removes it, and CTRL/C stops the
program again. Since `Platform` does not import `AsynchronousTraps`, a
handler that uses `NEW` needs the import shown. With no terminal, in a
batch job, the handler is kept and never called.

### Traps and conditions at AST level

A trap at AST level, such as an index out of range, ends the program as
anywhere, with its message and status. A condition signalled at AST level
is offered to the AST routine's handlers, and then to the handlers of
the frames the AST interrupted, which belong to code that is not
running. So a handler must not unwind at AST level: it tests
`AsynchronousTraps.InProgress` first (chapter 13).

## 15. Subprocesses

*For the Unix reader: what VMS has instead of `fork`, `exec` and
`wait`. For the VMS reader: `LIB$SPAWN` from Oberon, and its quotas.*

VMS has no `fork`. A program runs a command in a **subprocess**, a new
process with its own DCL, made by `LIB$SPAWN`, which runs one command or
a command procedure and then ends. The subprocess belongs to the
program's job, and by default it starts with copies of the program's DCL
symbols, process logical names and keypad state. Making a process is
much slower than a Unix `fork`: a program that runs many commands does
better to write them to one command procedure and spawn that once.

### `Platform.System`

`Platform.System(command)` is the portable way, as on the Unix targets.
It runs the DCL command in a subprocess and waits for it, and returns:

- **0** when the command's final status is a success;
- **the final status** otherwise, its low word under `-O2`, where
  `INTEGER` has 16 bits;
- **-1** when no subprocess could be made, or the command is too long.

### `Run`

`Subprocesses.Run(command, input, output, options, completion)` does the
same, and says more. Its result is `LIB$SPAWN`'s, which says whether the
subprocess was made, and the command's final status comes back in
`completion`. Either is a condition value, so test it with `ODD`.

- **`input`** is a file the subprocess reads as `SYS$INPUT`. With an
  empty `command`, DCL takes its commands from it, so a command
  procedure can be run so.
- **`output`** is a file the subprocess writes as `SYS$OUTPUT` and
  `SYS$ERROR`. Left empty, it is the program's own output, a file
  included.
- **`options`** is a set of `Subprocesses.noSymbols`, `noLogicalNames` and
  `noKeypad`, each of which keeps the subprocess from copying that.

A command that fails leaves its message where DCL writes messages, the
subprocess's `SYS$OUTPUT`, as it does at the terminal. This program runs
a command that succeeds, one that fails twice (status 44 is
`SS$_ABORT`), and then two that it does not wait for:

<!-- example: vax/spawn/Spawn.Mod -->
```
MODULE Spawn;
  IMPORT SYSTEM, Out, Platform, Subprocesses, Timers, LIB_ROUTINES, JPIDEF;

  VAR
    status, completion: SYSTEM.INT32;
    result: INTEGER;
    job: Subprocesses.Subprocess;

  (* waits, at most 10 seconds, until VMS has deleted every subprocess of
     this process that has ended, so that the next one fits the quota *)
  PROCEDURE AwaitNone;
    VAR count, status: SYSTEM.INT32; tries: INTEGER;
  BEGIN
    tries := 0;
    REPEAT
      count := 0;
      status := LIB_ROUTINES.LIB$GETJPI(JPIDEF.JPI$_PRCCNT, NIL, NIL, count, NIL, NIL);
      IF count # 0 THEN status := Timers.Sleep(100); INC(tries) END
    UNTIL (count = 0) OR (tries = 100)
  END AwaitNone;

  PROCEDURE Report(what: ARRAY OF CHAR; status, completion: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF ~ODD(status) THEN Out.String("not started, %X"); Out.Hex(status, 8)
    ELSIF ODD(completion) THEN Out.String("succeeded")
    ELSE Out.String("failed, %X"); Out.Hex(completion, 8)
    END;
    Out.Ln
  END Report;

  PROCEDURE YesNo(what: ARRAY OF CHAR; answer: BOOLEAN);
  BEGIN
    Out.String(what); Out.String(": ");
    IF answer THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END YesNo;

BEGIN
  status := Subprocesses.Run('WRITE SYS$OUTPUT "from a subprocess"', "", "", {}, completion);
  Report("WRITE", status, completion);

  AwaitNone;
  status := Subprocesses.Run("EXIT 44", "", "", {}, completion);
  Report("EXIT 44", status, completion);

  AwaitNone;
  result := Platform.System("EXIT 44");
  Out.String("Platform.System: "); Out.Int(result, 0); Out.Ln;

  AwaitNone;
  status := Subprocesses.Start("WAIT 00:00:01", "", "", {}, job);
  YesNo("ended at once", Subprocesses.Done(job));
  completion := Subprocesses.Wait(job);
  YesNo("ended after Wait", Subprocesses.Done(job));
  Report("WAIT 00:00:01", status, completion);

  AwaitNone;
  status := Subprocesses.Start("WAIT 00:01:00", "", "", {}, job);
  status := Subprocesses.Stop(job);
  Report("WAIT 00:01:00, stopped", status, Subprocesses.Wait(job))
END Spawn.
```

<!-- vax-session: spawn -->

    $ RUN SPAWN
    from a subprocess
    WRITE: succeeded
    %SYSTEM-F-ABORT, abort
    EXIT 44: failed, %X0000002C
    %SYSTEM-F-ABORT, abort
    Platform.System: 44
    ended at once: no
    ended after Wait: yes
    WAIT 00:00:01: succeeded
    WAIT 00:01:00, stopped: succeeded

The program's output and its subprocesses' go to the same place in the
order they were written. `Out` writes a line when it ends, so a line
started before a spawn appears after what the subprocess wrote.

### `Start`, `Done`, `Wait` and `Stop`

`Subprocesses.Start` takes the same arguments as `Run`, less
`completion`, and gives back a `Subprocesses.Subprocess` instead of
waiting. The program goes on while the command runs. Then:

- **`Done(s)`** tells whether it has ended, without waiting.
- **`Wait(s)`** waits until it has ended, and returns its final status.
  It can be called again, and returns the same.
- **`Stop(s)`** deletes it at once (`$DELPRC`). `Wait` then returns
  `SS$_NORMAL`, as the example shows.
- **`Id(s)`** is its process identification, for `$GETJPI` and the like.

VMS writes the final status of a subprocess not waited for into the
program's memory when it ends, so `Subprocesses` keeps each `Subprocess`
from `Start` until `Wait` has seen it end, and the collector cannot free
it meanwhile. A program may drop one it does not care about, but each
that is not waited for keeps one of the process's local event flags
(`EventFlags`, chapter 8) for as long as the program runs.

### Quotas

A process may have only as many subprocesses at once as its `PRCLM`
quota allows, often a small number: 2 on the development system that
checks this guide. Past it, `LIB$SPAWN` fails with `SS$_EXQUOTA`. A
subprocess that has ended still counts until VMS has deleted it, which
happens a little later, so a program that spawns one right after another
has ended can still be refused. `AwaitNone` in the example waits for the
count to reach 0, by asking `LIB$GETJPI` for `JPI$_PRCCNT`, the number of
subprocesses the process has. `SHOW PROCESS/QUOTAS` shows how many more it may have.

### ASTs and subprocesses

`Run`, `Platform.System` and every other `LIB$SPAWN` that waits
hibernate in supervisor mode. The program's ASTs (chapter 14) are
user-mode ones, and wait until the subprocess has ended: a
`Timers.After` that expires meanwhile is delivered after `Run` returns.

A program that wants an AST when a subprocess ends calls `LIB$SPAWN`
itself, from `LIB_ROUTINES`, with `CLI$M_NOWAIT`, a routine and its
parameter. The final status goes to an address the program gives, which
must stay valid until the subprocess has ended: a global variable.

    VAR finalStatus: SYSTEM.INT32; ...
    status := LIB_ROUTINES.LIB$SPAWN('WRITE SYS$OUTPUT "for the AST"', NIL, "SPAWN.OUT",
      CLIDEF.CLI$M_NOWAIT, NIL, NIL, SYSTEM.ADR(finalStatus), NIL, Completed, 7,
      NIL, NIL, NIL)

`Completed(parameter)` is called with 7 at AST level when the subprocess
has ended, under chapter 14's rules.

### When `LIB$SPAWN` fails

The usual failures are these:

- **`SS$_EXQUOTA`**: too many subprocesses, above.
- **`LIB$_NOCLI`**: the program has no DCL. It was run as a subprocess
  or detached process by `RUN/DETACH` or `$CREPRC` directly, not by a
  command, so it has no DCL to copy.
- **`SS$_DUPLNAM`** and **`SS$_IVLOGNAM`**: a process name given to
  `LIB$SPAWN` is already in use in the group, or is longer than 15
  characters. `Subprocesses` gives none, and VMS makes one up.

### Running another image instead

Two `LIB$` routines end the program and have DCL go on with something
else. Both end it by `$EXIT`, so its exit handlers run, poc's among
them, which writes `Out`'s last line and runs the finalizers (chapter 13):

- **`LIB$RUN_PROGRAM(name)`** runs another image in the same process,
  as the `RUN` command would.
- **`LIB$DO_COMMAND(command)`** has DCL run one command next. In a
  command procedure, the procedure then goes on with its next line.

`LIB$PUT_COMMON` and `LIB$GET_COMMON` pass a string of up to 252
characters to the next image in the process. The `LIB$` manual calls
that "not recommended", and a foreign command's arguments (chapter 6) or
a logical name (chapter 8) do as well. `LIB$ATTACH` moves the terminal
to another process of the job, as DCL's `ATTACH` does.

## 16. When a program fails on VMS

*For the Unix reader: what VMS prints when a program fails, and how to
find the line at fault. For the VMS reader: what poc's programs add to
the traceback you know.*

A program fails in one of three ways. One of poc's checks finds an
error, and **traps**. The hardware or a VMS routine signals a condition
that no handler deals with, a **fault** such as a division by zero.
Or the program **does not start** at all, because an image it needs
cannot be activated, as chapter 4 shows. This chapter takes the first
two in turn, then the debugger, for a program that runs but does the
wrong thing.

### A trap

A trap writes poc's message to `SYS$ERROR` and ends the program with a
status that names the trap, as chapter 5's table shows. Its exit
handlers still run, poc's among them, which writes `Out`'s last line
and runs the finalizers. Built with `-trap-location`, the message also
says where, by file, line and column, and in which procedure:

<!-- example: vax/fail/Fail.Mod -->
```
MODULE Fail;
  IMPORT Out;

  VAR counts: ARRAY 10 OF INTEGER;

  PROCEDURE Count(digit: INTEGER);
  BEGIN
    INC(counts[digit])
  END Count;

BEGIN
  Count(3); Count(10);
  Out.String("not reached"); Out.Ln
END Fail.
```

<!-- vax-session: fail -->

    $ RUN FAIL
    Fail.Mod:8:16: index out of range (in Fail.Count)
    $ SHOW SYMBOL $STATUS
      $STATUS == "%X10000012"

The file is named as it was given to poc. DCL prints no message of its
own for the status, since poc's has said what happened. A command
procedure tests the status as any other: `.NOT. $STATUS` is true after a
trap, and `($STATUS .AND. %XFFF8) / 8` is the trap's code, 2 here.

### A fault and its traceback

A fault is a condition, and with no handler of the program's (chapter
13) VMS's last one prints its message and a **traceback**, the calls
that led to it, newest first, and ends the program with the condition
as its status:

<!-- example: vax/fault/Fault.Mod -->
```
MODULE Fault;
  IMPORT Out;

  VAR none: INTEGER;

  PROCEDURE Average(total, count: INTEGER): INTEGER;
  BEGIN
    RETURN total DIV count
  END Average;

BEGIN
  Out.Int(Average(10, 2), 0); Out.Ln;
  Out.Int(Average(10, none), 0); Out.Ln
END Fault.
```

<!-- vax-session: fault -->

    $ RUN FAULT
    5
    %SYSTEM-F-INTDIV, arithmetic trap, integer divide by zero at PC=00002032, PSL=03C00004
    %TRACE-F-TRACEBACK, symbolic stack dump follows
    module name     routine name                     line       rel PC    abs PC

    FAULT           FAULT_AVERAGE_5CV3RD9U                     00000006  00002032
    FAULT           FAULT_INIT                                 00000043  0000206F
    FAULT           FAULT_MAIN                                 00000017  00002097

Each line is a call: the module, the routine, and the PC, relative to
the routine's start and absolute. The routines are poc's VAX symbols
(chapter 5): a module's body is `<MODULE>_INIT`, and the program's start,
which calls it, `<MODULE>_MAIN`. A procedure is its module and name,
uppercased and cut to 22 characters, with `_` and eight characters of a
hash after it, so `FAULT_AVERAGE_5CV3RD9U` is `Fault.Average`.

Two things VMS does make a traceback harder to read:

- **The line column is empty.** It holds a line only for a module
  assembled with `/DEBUG` in a program linked `/DEBUG`, below.
- **Far into a long routine, the routine is not named.** For a PC more
  than about a kilobyte past a routine's start, the traceback names the
  program section `POC_CODE` instead, with the PC relative to the
  section. The next line down, the routine's caller, is still right.

### Line numbers in a traceback

poc writes each module as MACRO-32, `<MODULE>.MAR`, with a comment
`; line n` before the code of line *n* of the Oberon source. Assembled
with `/DEBUG`, a module's routines get line numbers, those of its `.MAR`
file, and in a program linked `/DEBUG` the traceback shows them. To find
the line of a fault, assemble that module so, link the program again as
its build procedure does but with `/DEBUG`, and run it with `/NODEBUG`,
so that the debugger does not start:

<!-- vax-session: faultdebug -->

    $ MACRO/DEBUG/OBJECT FAULT.MAR
    $ LINK/DEBUG/EXECUTABLE=FAULT.EXE FAULT.OPT/OPTIONS, POCRTL.OBJ
    $ RUN/NODEBUG FAULT
    5
    %SYSTEM-F-INTDIV, arithmetic trap, integer divide by zero at PC=00002032, PSL=03C00004
    %TRACE-F-TRACEBACK, symbolic stack dump follows
    module name     routine name                     line       rel PC    abs PC

    FAULT           FAULT_AVERAGE_5CV3RD9U             38      00000006  00002032
    FAULT           FAULT_INIT                         82      00000043  0000206F
    FAULT           FAULT_MAIN                         98      00000017  00002097

Line 38 of `FAULT.MAR` is the `DIVW3` instruction, and the comment above
it is `; line 8`, the `RETURN` of `Average`. Line 82 is the call in the
body, after `; line 13`, and line 98 the call of the body. The build procedure, `FAULT.COM`, links with
`POC$RTL:POCRTL.OBJ` when that logical name is defined (chapter 2), and an
import's module can be assembled
`/DEBUG` in the same way.

### The debugger

For a program that runs but does the wrong thing, the VMS debugger
works on poc's programs as on any MACRO-32 program. Assemble the
modules to be looked at with `/DEBUG`, link with `LINK/DEBUG`, and `RUN`
the program: the debugger starts before the program does. Its source
is the `.MAR` files, so `SET BREAK`, `STEP`, `EXAMINE` and `DEPOSIT` work
with the VAX symbols and the `.MAR` lines, and the `; line n` comments
lead back to the Oberon source. `SET MODULE/ALL` makes every module's
symbols known, and `SET RADIX DECIMAL` shows numbers as Oberon writes
them. A global variable is a symbol like a procedure's,
`FAULT_NONE_<hash>` for `Fault.none`; a local one is an offset from
`FP` in its procedure's code.

### Other failures

- **`%SYSTEM-F-ACCVIO`**, an access violation. poc's checks catch a NIL
  pointer and an index out of range, so in a poc program an access
  violation comes from `SYSTEM.GET`, `PUT` or `MOVE`, or from a VMS
  routine declared with the wrong arguments (chapter 7).
- **`%SYSTEM-F-FLTOVF_F`** and **`%SYSTEM-F-FLTDIV_F`**: a real overflow
  or a division by zero, which a VAX has no infinity for (chapter 5).
- **`%SYSTEM-F-EXQUOTA`**: a process quota is used up, as a
  subprocess's (chapter 15) or a timer's (chapter 14) can be. `SHOW
  PROCESS/QUOTAS` shows what is left.
- **A file that cannot be created or written** stops the program with
  `Files`' message and `HALT(99)` (chapter 6).
- **A status from a VMS routine** that a program prints as a number is
  turned into its message by `Conditions.Message` (chapter 8), or in
  DCL by `F$MESSAGE`: `WRITE SYS$OUTPUT F$MESSAGE(%X0000002C)` prints
  `%SYSTEM-F-ABORT, abort`.

## 17. poc on VMS itself

*For the VMS reader, and for whoever looks after poc on a VMS system.*

### What `POC.EXE` is

`POC.EXE` is poc, compiled for the VAX by poc itself on Unix. The base
kit carries the MACRO-32 that compilation wrote, in `[.KIT]`, and
`@BUILD` assembles and links it on VMS with MACRO and LINK alone
(chapter 1). It has the same front end and VAX back end as poc on Unix,
so it accepts the same language and writes the same MACRO-32 for the
same source. It has no LLVM back end, and refuses the options that only
that back end has (chapter 3).

`SETUP.COM` defines `POC` as a foreign command, `POC :== $<image>`, so
poc takes its arguments as on Unix, options starting with `-`, rather
than as DCL qualifiers. DCL makes an argument uppercase unless it is
quoted, and poc takes options in any case, as file names on VMS are.
`POC -HELP` lists them all. An argument `@<file>` stands for the
arguments in the file, one a line, for a command longer than DCL takes
(chapter 3).

### What poc needs to run

**Privileges and products:** none. poc, `@BUILD` and the programs they
build need only the base system's MACRO, LIBRARY and LINK.

**Memory:** poc keeps a whole program's modules in memory while it
compiles them, and its heap grows as it needs. A program of a few
modules needs little. The most it has needed is to compile itself,
about 32,000 lines: a peak of about 90 MB of virtual memory. On the development system that does so, the process has
`PGFLQUOTA` 300,000 pages (150 MB), `WSQUOTA` 8,192 and `WSEXTENT`
16,384, and the system `VIRTUALPAGECNT` 350,000 pages and a paging file
of 350,000 blocks, on a VAX with 256 MB of memory. A process with less
can still compile the programs that fit it. The quotas are set with
`AUTHORIZE`, and the system's parameters with `SYSGEN`, by the system
manager.

**Time:** on the emulated MicroVAX 3900 that poc was developed on,
`@BUILD` of the base kit takes about a minute: `POC.EXE` half of it,
then `POCRTL` under each size model. The STARLET kit adds about another
minute, nearly all of it `VMSDEF`. poc compiling itself has taken from
a quarter of an hour to three quarters of one there, as the
emulator's speed varies. A real MicroVAX is likely
to be slower than its emulation on a modern computer.

### poc for several users

poc is installed once, in a directory its users can read. Each user
runs its `SETUP.COM`, from `LOGIN.COM` for instance, which defines the
command `POC` and the libraries' logical names in the user's process.
The installation's directories and files must allow the users read and
execute access, which DCL's `SET FILE/PROTECTION` gives. A user's own
libraries are made and set up as chapter 4 says, in the user's own
directories.

### Building poc from its source on VMS

`[.SRC]` holds poc's own source, as much of it as poc for VMS is built
from, with the runtime's. poc can compile itself from it, under `-OC`,
since poc needs a 64-bit `LONGINT`, and from source alone, without the
installed libraries. The command is longer than DCL takes, so its
arguments go in a file, one a line, here `FULL.ARGS` in a new directory
beside `[.SRC]`:

    -OC
    -clear-library-path
    -import-path
    [-.SRC.FRONT]
    -import-path
    [-.SRC.BACK.VAX]
    -import-path
    [-.SRC.DRIVER]
    -import-path
    [-.SRC.DRIVER.NO-LLVM]
    -import-path
    [-.SRC.RTL]
    -import-path
    [-.SRC.GEN]
    -build
    [-.SRC.DRIVER]POC.MOD

`[.SRC.DRIVER.NO-LLVM]` stands in for the LLVM back end, which poc for
VMS leaves out. Then:

    $ POC @FULL.ARGS
    $ @POC

The first writes poc's MACRO-32, one `.MAR` for each module, and
`POC.COM`. The second assembles them and links a new `POC.EXE`, with
`POCRTL.OBJ` assembled from `[.SRC.RTL]POCRTL.MAR`, as `[.KIT]`'s
procedure does.

poc is a **fixed point**: compiled by itself, it writes the same
MACRO-32 as the poc that compiled it. The `.MAR` files written here are
the same as `[.KIT]`'s, line for line, which `DIFFERENCES` can show for
each one. poc's developers check that on the development system, and a
third generation too: the `POC.EXE` linked here, compiling the same
source again, writes the same files once more.

### A new version

Each version of poc is a kit of its own, unpacked into a new, empty
directory: the STARLET kit refuses to unpack over another version's base
kit. Once it is built and set up, the new version is used by running its
`SETUP.COM` in place of the old one's.

Libraries do not move between versions. poc refuses a library another
version wrote, since nothing promises that two versions' code links
together, so a user's own libraries are made again with the new poc,
from their source. A program linked from object libraries carries what
it uses and goes on running. A program linked with `-shared-libraries`
needs the images it was linked against, so it is linked again when they
change (chapter 4 shows the messages otherwise).

To remove a version, delete its directory tree, and the lines in
`LOGIN.COM` that run its `SETUP.COM`.

## Appendix A. The kits' contents

Each kit unpacks into the directory it is run in, which the base kit
needs empty. These are the directories and files they make, and what
`@BUILD` (chapter 1) adds.

### The base kit, `POC-<version>.COM`

| Where | What |
|---|---|
| `README.TXT` | How to install and use poc, as chapter 1 says |
| `BUILD.COM` | Builds `POC.EXE` and every library that is unpacked and not yet built; each step's time goes to `BUILD.LOG` |
| `SETUP.COM` | Defines the command `POC` and the logical names of one size model's libraries, `-O2`'s or, with `@SETUP OC`, `-OC`'s |
| `VERSION.TXT` | One line, the version and the commit it was made from; the STARLET kit checks it |
| `LICENSE.TXT` | poc's license |
| `[.BIN]` | Empty; `@BUILD` puts `POC.EXE` here |
| `[.KIT]` | poc's own MACRO-32, as poc on Unix writes it for poc's source: a `.MAR` for each module, the procedure that assembles and links them, and the runtime's `POCRTL.MAR`. `@BUILD BOTH CLEAN` deletes it once `POC.EXE` is built |
| `[.LIB.POC.VAX-DEC-VMS.O2]`, `[.OC]` | The library `POCRTL`, poc's runtime, for each size model, as `poc -library` writes it (chapter 4): its manifest, `POCRTL_BUILD.COM` and `POCRTL_SETUP.COM`, and each module's `.MAR`, `.SYM` and `.OWNER` (the name of the library the module belongs to). `@BUILD` adds `POCRTL.OLB` and `POCRTL.EXE` |
| `[.SRC...]` | The Oberon source `POC.EXE` is compiled from: the front end, the VAX back end, the driver, and the runtime's modules (chapter 17) |

### The STARLET kit, `POC-VMS-<version>.COM`

It refuses to unpack anywhere but in the top of a base kit of its own
version, and only once.

| Where | What |
|---|---|
| `README-VMS.TXT` | What the kit holds, and how to build and use it |
| `[.LIB.POC.VAX-DEC-VMS.O2]`, `[.OC]` | The libraries `VMSDEF` (chapter 9) and `VMSLIB` (chapter 8), as `POCRTL` is: each its manifest, its two procedures and its modules' files. `@BUILD` adds each one's `.OLB` and `.EXE` |
| `[.SRC.RTL.VMS]` | `VMSDEF`'s source: the modules generated from `SYS$LIBRARY:STARLETSD.TLB`, one for each of its modules |
| `[.SRC.RTL.VMSLIB]` | `VMSLIB`'s source: its twelve modules |

The STARLET kit is about half the base kit's size but has most of the
files, about 1,700, since `VMSDEF` has a module for each of STARLET's.

## Appendix B. What is left out, and why

poc reaches most of VMS 5.5-2 through `VMSDEF`, and chapter 9 lists what
has been tried. Some things are left out, each for a reason. Any of them
can come later if a program needs it.

### From the language

- **`SYSTEM.CC`, `GETREG` and `PUTREG`**, as on Unix.
- **D_floating, H_floating and complex numbers.** `LONGREAL` is
  G_floating (chapter 5), and poc has no type for the others, so the
  routines of `MTH$` and `OTS$` that take or return them are declared,
  with their values as 8 or 16 bytes, but nothing computes with them.
- **voc's library modules** (the *User's Guide*, chapter 11), which poc
  for Unix does not have either.

### From VMSDEF

Generated, but not tried and not described here:

- **The privileged services**, those that need a privilege a user
  account does not normally have: `$CMKRNL`, `$CMEXEC`, the rights
  database's writers, `$SETUAI`, `$SETIME`, `$LCKPAG`, `$ULKPAG`,
  `$SETSWM`, `$SNDERR`, `$GRANTID` and `$REVOKID`; and `$ADJSTK`, which
  the VMS manual reserves to the system.
- **`NCS$`**, national character sets, which an ASCII Oberon program has
  no use for yet.

Not declared at all, each with a comment in its module (chapter 9):

- **Routines with a variable number of arguments**, such as `SYS$FAO`,
  `LIB$SIGNAL`, `LIB$STOP` and `STR$CONCAT`. `Conditions` signals and
  stops (chapter 13), `SYS$FAOL` takes its arguments as an array, and a
  declaration of your own with a fixed number of arguments serves too
  (chapter 7).
- **DECthreads** (`CMA`), which is for C alone in 5.5. Threads would
  also interrupt the collector in a way it is not made for.

### Facilities

- **The vector services and `MTH$`'s vector routines.** A VAX without a
  vector unit, such as the MicroVAX 3900 these were tried on, cannot use
  them.
- **DECdtm** (`$START_TRANS` and the rest), which needs a transaction log
  on the node, and **DECdns** (`$DNS`), which needs a name server.
- **`PPL$`**, parallel processing, which shares memory between
  processes: the collector's heap would need sharing too.
- **`DTK$`**, the DECtalk speech device.
- **Dynamic string descriptors** (`CLASS_D`). A routine's output is
  written into a fixed `CLASS_S` buffer with its length instead, which
  serves every routine but the few that only allocate and free dynamic
  strings, a job the collector does.
- **JSB entry points.** Every routine that has one has a CALL entry too,
  which poc uses.
- **`LIB$TPARSE`**, whose state tables are built by MACRO macros, and
  **`LIB$CRF_`**, cross-reference listings for a language processor.
- **`EDT$` and `TPU$`**, whose callbacks are bound procedure values,
  with an environment in a register, which Oberon's procedure values are
  not.
- **`PSM$` and `SMB$`**, print symbionts, which run in the queue
  manager's context.
- **`CLI$DISPATCH`**, since a program dispatches on the verb itself
  (chapter 10).

### Known behaviours a program must allow for

What VMS does here is left to the program:

- a `$EXIT` from an exit handler skips the handlers declared before it,
  poc's own among them (chapter 13);
- two RMS streams on one file in one process can lock each other out
  (chapter 11);
- a `SMG$` menu is chosen only on a terminal (chapter 12);
- `SortMerge`'s `noDuplicates` keeps one record of each key, but which
  one is SORT's choice, not necessarily the first: a program that cares
  calls `SOR_ROUTINES.SOR$BEGIN_SORT` itself, with a `user_equal`
  routine of its own.

## Appendix C. Further reading

### Oberon

- *The Programming Language Oberon-2*, H. Mössenböck and N. Wirth, in
  its later revision (`Oberon2.pdf`): the language poc compiles.
- The *Peaseblossom User's Guide* (`doc/users-guide.md`) and *Reference
  Guide* (`doc/reference-guide.md`): poc itself, its extensions to the
  language, and the runtime's modules, which this guide assumes.

### VMS

The manuals of the VMS 5.5 documentation set, or of the latest 5.x
release whose set has them, are the ones that describe the system poc
targets. Later OpenVMS manuals differ in details that matter. Most can
be found at bitsavers.org, under `pdf/dec/vax/vms/` and a directory
for each release. By their order
numbers:

| Subject | Manual | Order number |
|---|---|---|
| What changed in 5.5 | *VMS Version 5.5 Release Notes*, *New Features Manual* | `AA-LB22D`, `AA-LA97D` |
| Which manual covers what | *Overview of VMS Documentation*, *Programming Master Index* | `AA-LA95D`, `AA-LA56C` |
| System services | *Introduction to VMS System Services* and *VMS System Services Reference Manual* (5.5) | `AA-LA68B`, `AA-LA69B` |
| The calling standard, condition handling | *Introduction to VMS System Routines* (5.4) | `AA-LA66B` |
| The run-time library | *Introduction to the VMS Run-Time Library*; the `LIB$`, `STR$`, `MTH$`, `OTS$` and `SMG$` manuals | `AA-LA70A`; `AA-LA76A`, `AA-LA75A`, `AA-LA72B`, `AA-LA73A`, `AA-LA77A` |
| RMS | *VMS Record Management Services Manual*, *Guide to VMS File Applications*, *Guide to VMS Files and Devices* | `AA-LA83A`, `AA-LA78A`, `AA-LA06A` |
| `$QIO` and devices | *VMS I/O User's Reference Manual*, parts 1 and 2 | `AA-LA84B`, `AA-LA85A` |
| Callable utilities (`CLI$`, `SOR$`, `LBR$` ...) | *VMS Utility Routines Manual* (5.4) | `AA-LA67B` |
| Command tables | *VMS Command Definition Utility Manual* | `AA-LA60A` |
| Linking, shareable images | *VMS Linker Utility Manual*, *VMS Librarian Utility Manual*, *VMS Install Utility Manual* | `AA-LA62A`, `AA-LA61A`, `AA-LA29A` |
| MACRO-32 | *VAX MACRO and Instruction Set Reference Manual* (5.4) | `AA-LA89B` |
| DCL | *VMS DCL Dictionary* (5.4), *Guide to Using VMS Command Procedures* | `AA-PBK5A`, `AA-PBK6A`; `AA-LA11A` |
| Messages | *VMS Message Utility Manual* | `AA-LA63A` |
| The debugger | *VMS Debugger Manual* | `AA-LA59D` |
| Writing procedures to the standard | *Guide to Creating VMS Modular Procedures* | `AA-LA58A` |

### poc's VAX back end

For the curious, `doc/developer/` in poc's source describes how the VAX
back end works: `vax-macro32-backend.md` (code generation, the runtime,
libraries, ASTs and conditions), `vms-sdl-interfaces.md` (how `VMSDEF`
and `VMSLIB` are made) and, in `doc/research/`,
`vms-native-library-inventory.md` (what of VMS was chosen, and why).
