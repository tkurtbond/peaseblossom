Peaseblossom for VAX/VMS
========================

poc, the Peaseblossom Oberon compiler, for VAX/VMS 5.5-2: it compiles
Oberon-2 modules to VAX MACRO-32, and assembles and links them, with the
VMS base system's MACRO, LIBRARY and LINK, into images and libraries.
This kit is poc @VERSION@@COMMIT@, all of it text: poc's own MACRO-32,
which BUILD.COM assembles and links here, with its runtime library. It
needs no privilege and nothing beyond the base system. A second kit,
POC-VMS-@VERSIONNAME@.COM, adds VMS's own interfaces (below).

Installing
----------

1. Copy POC-@VERSIONNAME@.COM to VMS in ASCII (text) mode: with FTP,
   "ascii" before "put". A binary copy is stored as fixed 512-byte records
   and will not run.

2. Make an empty directory for poc, at most four names deep, and unpack
   the kit there:

       $ CREATE/DIRECTORY [.POC]
       $ SET DEFAULT [.POC]
       $ @[-]POC-@VERSIONNAME@

   It makes [.BIN], [.KIT], [.LIB.POC.VAX-DEC-VMS.O2] and [.OC], [.SRC],
   BUILD.COM, SETUP.COM, this README.TXT, VAX-VMS-GUIDE.TXT, LICENSE.TXT
   and VERSION.TXT.

3. Build poc and its libraries:

       $ @BUILD

   This assembles and links POC.EXE into [.BIN] from [.KIT]'s MACRO-32,
   then builds the library POCRTL, poc's runtime, under both size models.
   It takes a while: each step's time is added to BUILD.LOG. "@BUILD O2"
   or "@BUILD OC" builds only one size model's libraries; "@BUILD BOTH
   CLEAN" deletes [.KIT] once POC.EXE is built. @BUILD builds only what
   is not built yet; to build something again, delete it (POC.EXE, or a
   library's .OLB) first.

4. Make poc usable in a process, and add this line to LOGIN.COM:

       $ @dev:[dir]SETUP

   SETUP.COM defines the command POC and the logical names of the -O2
   libraries. "@SETUP OC" chooses the -OC libraries instead: a process
   builds against one size model's at a time.

VMS's own interfaces: the STARLET kit
-------------------------------------

POC-VMS-@VERSIONNAME@.COM holds two more libraries, with their sources:
VMSDEF, VMS's system services, run-time library routines, condition
values and data structures as Oberon modules (STARLET, LIB_ROUTINES,
SSDEF, ...), generated from SYS$LIBRARY:STARLETSD.TLB, and VMSLIB
(BalancedTrees, CommandLanguage, Conditions, DateTimes, DecimalStrings,
EventFlags, ExitHandlers, LogicalNames, SortMerge, Subprocesses, Symbols
and Timers), built on them. It is about half
this kit's size but has most of the files, about 1,700. Copy it in ASCII
mode, and run it in the top of this installation, now or later, then
build and set up again:

    $ @POC-VMS-@VERSIONNAME@
    $ @BUILD
    $ @SETUP

It refuses to unpack anywhere but in the top of a poc of its own
version, and @BUILD then builds only VMSDEF and VMSLIB. README-VMS.TXT,
which it writes, says more.

Using poc
---------

    $ POC HELLO.MOD
    $ @HELLO
    $ RUN HELLO

POC compiles HELLO.MOD and the modules it imports to MACRO-32 and writes
HELLO.COM, which assembles them and links HELLO.EXE against the
libraries.

"POC -HELP" lists poc's commands and options; options may be typed in any
case. "POC -OC ..." compiles for the -OC size model (INTEGER 32 bits,
LONGINT 64), with "@SETUP OC" first. The libraries are linked from their
object libraries, or with -shared-libraries from their shareable images,
which a program then needs at run time through the logical names SETUP.COM
defines. "POC -VERSION" prints poc's version and target.

poc finds a module's interface on its import path, the logical name
POC$IMPORT, and libraries in [.LIB.POC] beside its [.BIN], then on the
search list POC$LIBRARY.

poc for VAX/VMS has no LLVM back end: it compiles for VAX/VMS only, and
refuses the options that only the LLVM back end has (-lto, -g and so on).

[.SRC] holds poc's own source, as much as poc for VMS is built from, and
the runtime's and libraries' sources. poc can compile itself, under -OC
and from source alone, with its arguments in a file, one a line (an
argument @<file> stands for them):

    -OC
    -clear-library-path
    -import-path
    [-.SRC.FRONT]
    -import-path
    [-.SRC.BACK.VAX]
    -import-path
    [-.SRC.BACK.VAX.VMS]
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

Saved as FULL.ARGS in a new directory beside [.SRC], "POC @FULL.ARGS"
there writes poc's MACRO-32 and POC.COM, which assembles it and links
POC.EXE, with POCRTL.OBJ assembled from [.SRC.RTL]POCRTL.MAR, as [.KIT]'s
did; on the emulated MicroVAX 3900 (SIMH) poc was developed on, that
took about 45 minutes.

VAX-VMS-GUIDE.TXT is the Peaseblossom VAX/VMS Guide, which says all of
this at more length, and how a program reaches VMS's own facilities:

    $ TYPE/PAGE VAX-VMS-GUIDE.TXT

It, Peaseblossom's User's Guide and Reference Guide, and its source, are
at https://github.com/tkurtbond/peaseblossom. LICENSE.TXT is its license.
