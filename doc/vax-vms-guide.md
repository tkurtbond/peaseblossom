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

<!-- Chapter 6, the runtime modules on VMS, is to be written. -->

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

<!-- Chapters 8 to 17 and the appendices are to be written (the outline,
PLAN.md Phase 17 step 8). -->
