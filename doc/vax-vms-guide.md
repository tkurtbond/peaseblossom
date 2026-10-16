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

<!-- Chapters 11 and 12 are to be written. -->

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

<!-- Chapters 14 to 17 and the appendices are to be written. -->
