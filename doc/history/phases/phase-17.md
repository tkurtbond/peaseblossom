# Phase 17 — Detailed library/module support for VAX/VMS

Moved here from `PLAN.md` on 2026-10-16, once the phase was done, with
the exit review written at the close-out. `PLAN.md` keeps the heading,
the goal and a list of the steps. The design behind each step, every
decision with its date, and the facts with their sources in the VMS 5.x
manuals are in three places: `doc/developer/vax-macro32-backend.md`,
sections 18-23 (step 1's libraries, section 18; step 3's modules,
section 19; `main`'s unsigned types on the VAX, section 20; step 7's
kit, section 21; step 6's ASTs and part 11's `LIB$`, section 22; part
5's `CLI$`, section 23);
`doc/developer/vms-sdl-interfaces.md` (step 5, parts 1-12); and the two
inventories of steps 2 and 4, `doc/research/vms-module-inventory.md` and
`doc/research/vms-native-library-inventory.md`.

The phase's text in `PLAN.md`, as it stood:

**Goal**: for VAX/VMS, what Phase 12 did for the LLVM targets - libraries
poc can build and programs can link against, a decision about which
existing Oberon modules to support - and then what only VMS has: its own
native libraries, and asynchronous system traps. It is the same
investigation-first shape as Phase 12: steps 1, 2 and 4 write down
inventories and decisions from primary sources (the VMS and VAX manuals
kept locally under `~/Reference/Computer/OS/VMS` and `.../Systems/VAX`
- among them the VAX MACRO reference, the VMS system software and
programming-environment manuals, the RMS and VAX C RTL manuals, and the
DEC MMS guide) before steps 3, 5 and 6 build anything.

**Explicit non-goals**: the LLVM targets (Phase 12); VMS versions and
architectures other than VAX 5.5-2; layered products (DECwindows, DEC
C++, and so on) unless step 4 chooses one deliberately.

1. **Static and dynamic libraries on VMS.** Work out how poc builds them
   and how a program links against them - this is the first thing, because
   step 3 and step 5 both put modules in libraries. The VMS analogues,
   to be confirmed against the manuals and then tried: an **object library**
   (`LIBRARY/CREATE`, `.OLB`, with `LINK prog, lib/LIBRARY` pulling in only
   the modules that resolve undefined symbols) for the static case;
   a **shareable image** (`LINK/SHAREABLE`, activated at run time, installed
   with `INSTALL` where a system-wide one is wanted) for the dynamic case.
   Questions that are specific to the VAX: shareable-image code must be
   position independent, so `VaxCodeGenerator.Mod` must emit PC-relative
   references and the right program-section attributes (`PIC`, `SHR`,
   `NOSHR`, `WRT`) for code, constants and per-process data - which may
   change code Phase 16 already emits; how a shareable image exports
   its entry points (transfer vectors, universal symbols, or the linker's
   symbol-vector option, whichever 5.5-2 has), and how a *version* is
   expressed (`GSMATCH` and major/minor identification) so that the layout
   guarantee `.sym` files give importers holds across a rebuild; the same
   31-character symbol limit and Phase 15's mangling, which must now be
   stable across separately built libraries (a hash suffix must not depend
   on what else was in the compilation); where the collector and module
   registry live when there is more than one image, and what happens to
   writable data (it is per-process, and a shareable image gets its own
   copy of it); and how `.sym` files are found, through logical names or
   search lists rather than a Unix path. The build descriptions are MMS
   ones. **Testing**: a small library of a few dependent modules built
   both ways; a program linked against each and run; the failure cases
   (a `.sym` that does not match its image, a missing image, a version
   mismatch) reporting a message rather than crashing.

   **Record** (done, 2026-10-12): the survey of the 5.0 Linker
   and Librarian manuals, checked against the 5.5 and 5.5-2 release
   notes, and eight proposals are in `doc/developer/vax-macro32-backend.md`
   section 18, **approved by the user, 2026-10-12**. Found: 5.5-2 has no symbol
   vector (`UNIVERSAL=` and `.TRANSFER` only), and the build procedures
   are DCL, not MMS, as decided 2026-10-09 (Phase 16 step 1).
   Checked on the guest (section 18.4): a hand-written shareable image in
   poc's sections, reached by `G^` alone, resolves every kind of
   reference; a missing image, a relinked one and a wrong key each give
   a message; `[.VAX-DEC-VMS.OC]` is a usable directory.
   Done (section 18.5): `POC_ADDR`, the constants that hold addresses
   (type descriptors, `PocRtl`'s trap texts) out of `POC_CONST`
   (proposal 5).
   `-library` for the VAX (proposals 1, 2 and 4): `<name>_build.com`
   makes `<NAME>.OLB` and the shareable `<NAME>.EXE` on VMS,
   `<name>_setup.com` defines its logical names, and the runtime is the
   library `POCRTL`, which every other needs; fixture `vax-library`
   builds both on the guest and runs a program linked against each kind.
   Proposal 6 changed as the guest showed (section 18.5). `-build`
   links a program against VAX libraries, their object libraries or,
   with `-shared-libraries`, their shareable images, and `POCRTL`'s
   whenever it is on the library path (`vax-library` runs both on the
   guest). `-install-library` copies a VAX library's files, as text, the
   manifest now listing its parts. On VMS the library path is
   `-library-path`, the search list `POC$LIBRARY` and poc's own
   `[<parent>.LIB.POC]`, joined by `Directories.MakeSubdirectory`, which
   translates a logical name first (run on the guest by V1's poc); the
   import path's logical name is `POC$IMPORT` to match. DCL gives a
   foreign command at most 255 characters of arguments, so poc takes
   `@file` response files (everywhere) and expands `*` and `%` itself
   on VMS (section 18.5). Two exported names with one VAX symbol are
   refused when one or both modules come from a library, recomputed
   from their `.sym` files (proposal 7). On the guest, a missing image,
   an image relinked under an old program and a program compiled against
   another `.sym` each stop with VMS's message (proposal 8). Step 1 is
   complete; next, step 2.

2. **Which existing Oberon libraries and modules to support on VMS.**
   Take Phase 12's complete inventory of voc's modules and Phase 10's
   Oakwood set, and sort each for VAX/VMS: portable as they are; needing a
   VMS platform layer (`Platform`, `Files`, `Modules` - the ones written
   with the four Unix-likes in mind now need a fifth answer); depending on
   IEEE 754 (`Reals`, `MathL`, anything that takes a real apart into
   bits or assumes 64-bit doubles - VAX floating point is different, see
   Phase 16 step 3); depending on the C library, zlib or X11, none of which
   VMS 5.5-2 has by default; or hostile to ODS-2 file names. The output is
   a table of module and verdict, kept as a file the plan names, and the
   decisions.

   **Record** (done, 2026-10-12): the table is
   `doc/research/vms-module-inventory.md`. It covers poc's runtime,
   module by module: what `rtl/vax` has, what the VAX backend makes of
   `rtl/llvm`'s module, and what VMS must supply. It also covers voc's
   129 library modules: 51 need only poc's runtime, 17 take reals apart
   as IEEE, 55 are written for another system, and 6 need C or X11. Six
   proposals, **approved by the user, 2026-10-12**: step 3 is all of
   `rtl/llvm`'s interfaces in `POCRTL`; voc's libraries stay in Phase
   20; reals are converted by poc's own code, not VAXCRTL's; `Files`'
   typed riders write IEEE; `Math`/`MathL` go over `MTH$`; a part-line
   `Out.Flush` reaches a terminal. Next, step 3, starting with `Platform`.

3. **Implementing the chosen Oberon modules on VMS**, into step 1's
   libraries, in dependency order, each with fixtures shared with the LLVM
   side where the module is the same (the same `.mod` and `expected`, run
   on both), and VAX-specific fixtures where the behavior differs on
   purpose, documented where it differs.

   **Record** (in progress): `Platform` is done (2026-10-12): its eight
   proposals, **approved by the user, 2026-10-12**, are
   `doc/developer/vax-macro32-backend.md` section 19.1, and section 19.2
   records the work. It has voc's whole interface, over 18 new routines
   in `PocRtl.mar`. Fixture `vax-platform-files` runs 70 checks on the
   guest. `Files` is done (2026-10-12): its nine proposals, **approved by
   the user, 2026-10-12**, are section 19.3, and section 19.4 records the
   work. It has the whole interface, and its typed riders write IEEE
   reals. Fixtures `vax-files-riders` (`llvm-files-riders`' programs on
   the guest) and `vax-files-extra` (75 checks) are new. `Modules` is
   done (2026-10-13): its eight proposals, **approved by the user,
   2026-10-13**, are section 19.5, and section 19.6 records the work. It
   has the whole interface but `Init`. The VAX backend writes each
   module's descriptor in a program that contains `Modules`. Fixtures
   `vax-modules-commands` (`llvm-modules-commands`' programs) and
   `vax-modules-extra` are new. `RealDigits` and `Reals` are done
   (2026-10-13): their six proposals, **approved by the user,
   2026-10-13**, are section 19.7, and section 19.8 records the work.
   They come with a new `DecimalToReal` (correctly rounded decimal to F
   and G), `FormattedText` for the VAX, and `Out`'s and `Err`'s `Real`,
   `LongReal`, `Ten` and `IsConsole`. Fixtures `vax-real-digits`,
   `vax-reals-module` and `vax-out-reals` are new. `FormattedOutput` and
   `OutStr` are done (2026-10-13): their five proposals, **approved by
   the user, 2026-10-13**, are section 19.9, and section 19.10 records
   the work. `Out` and `Err` now format through `FormattedOutput`, as on
   LLVM, and `OutStr` is `rtl/llvm`'s. Fixture `vax-outstr` is new. `In`,
   `InStr` and `FormattedInput` are done (2026-10-13): their five
   proposals, **approved by the user, 2026-10-13**, are section 19.11, and
   section 19.12 records the work. `In` reads SYS$INPUT through
   `Platform`, which gives `Out`'s unfinished line as the prompt on a
   terminal, and reals are read by `DecimalToReal`. Fixtures `vax-in`,
   `vax-in-extra` and `vax-instr` are new. `Strings` is done
   (2026-10-13): its three proposals, **approved by the user,
   2026-10-13**, are section 19.13, and section 19.14 records the work.
   Its reals are read by `DecimalToReal`. Fixture `vax-strings-module` is
   new. `Math` and `MathL` are done (2026-10-14): their five proposals,
   **approved by the user, 2026-10-14**, are section 19.15, and section
   19.16 records the work. They call `MTH$` and `OTS$` through a new
   `PocRtl` routine, `POC_MATH`, which returns a signalled condition as a
   status. Fixtures `vax-math-module` and `vax-math-extra` are new.
   `Args` and `VT100` are done (2026-10-14): their four proposals,
   **approved by the user, 2026-10-14**, are section 19.17, and section
   19.18 records the work. `Out.Flush` writes a part line to a terminal
   without ending it, and `VT100` flushes each sequence. Fixtures
   `vax-args` and `vax-vt100` are new. `Texts` and `Oberon` are done
   (2026-10-14): their four proposals, **approved by the user,
   2026-10-14** (no `.Bak`, and no `HOME` or `USER`), are section 19.19,
   and section 19.20 records the work. `Texts` scans reals by
   `DecimalToReal` and keeps the old file as an older version, `Oberon`
   is `rtl/llvm`'s, and `Platform.getEnv` falls back to a DCL symbol.
   `Files.New("")` was fixed on the way. Fixtures `vax-texts` and
   `vax-oberon` are new. That is the last of the inventory's ten
   groups: every module of `rtl/llvm` has its VAX version, but for the
   internal `ModuleTable` and `FileDescriptorOutput`, whose work
   `PocRtl`'s `POC_ROOTS` and `LineOutput` do.

4. **Which native VAX/VMS libraries to support.** From the manuals, not
   memory, list what a VMS programmer expects to reach: the run-time
   library families (`LIB$` general utilities, `STR$` strings, `MTH$` and
   `OTS$` math and language support, `SMG$` screen management, `CLI$` and
   `LIB$GET_FOREIGN` for the command line); the system services (`SYS$`:
   `$QIO`, `$ASSIGN`, timers, mailboxes, locks, process and device
   information, logical names, and the rest); RMS, the record management
   services (`FAB`, `RAB`, and the `$OPEN`/`$GET`/`$PUT` family); and
   condition handling (`LIB$SIGNAL`, `LIB$STOP`, condition handlers,
   exit handlers). For each: what it is for, whether it is worth an Oberon
   interface, and what it costs. Record the choices, and what is left
   out and why.

   **Done (2026-10-14)**: `doc/research/vms-native-library-inventory.md`,
   seven proposals, **approved by the user, 2026-10-14**. Every one of
   `STARLETSD.TLB`'s 65 SDL modules is generated in step 5. A smaller
   tier gets fixtures on the guest: the synchronous system services
   listed there, RMS's relative and indexed files, parts of `LIB$`,
   `SMG$`, `SOR$`, and `STR$`'s decimal arithmetic. Three hand-written
   modules (`Conditions`, `LogicalNames`, `Symbols`) and a hand-declared
   `CLI$` complete it. The privileged and vector services, DECdtm,
   DECdns, DECthreads, `PPL$`, `DTK$`, D and H floating, and the
   utilities without SDL routines other than `CLI$` are left out, each
   for a reason the file records.

5. **Calling native libraries from Oberon.** The external-procedure
   declaration (`PROCEDURE ["VMS", ...]`, already accepted, recording only
   a convention and a linkage name) is not enough for VMS, and what more
   it needs is decided here. VMS routines take their arguments by
   *reference*, by *value*, or by *descriptor* (a string's class and
   length and address travel together), and return a condition value in
   `R0`; the declaration must say which mechanism each parameter uses, and
   the language needs a way to hold a string descriptor and an item list.
   The system's own definitions - the `$SSDEF` status codes, `$IODEF` function codes, RMS's control-block
   fields, item-list layouts - live in macro libraries (`STARLET.MLB`);
   decide whether a tool generates Oberon `CONST`/`RECORD` definition
   modules from them or they are written by hand, and how the generated
   modules track the kit they came from. STARLET's definitions are written
   in SDL, which renders them for each language (the macros in
   `STARLET.MLB`, VAX C's `ssdef.h` and the rest); the user maintains an
   UNSDL utility on a VAX that extracts much of that information, a
   likely starting point for the generator. The modules keep the system's
   names, `_` and `$` included (Phase 11 A25); SDL's unions and bit fields,
   which an Oberon record cannot express, need a convention of their own. Implement it, and write the
   interface modules step 4 chose, each with a fixture that calls the real
   service on the guest and checks a result.

   **First look** (2026-10-11, `doc/developer/vms-sdl-interfaces.md`):
   UNSDL is a set of SDL back ends that `SDL/NOPARSE` calls with the
   parsed tree of one of `STARLETSD.TLB`'s 65 modules, and a verb of its
   own (`unsdl.cld`) that runs `SDL/NOPARSE`; the guest has the library,
   `SDLNPARSE.EXE` and the `SDL` verb, so it runs there as it is. **Decided by the user
   the same day**: the generator, a back end of its own, runs on the VAX
   and is built with VAX C; the `.SDI` files are not read on the host.

   **Part 1, the mechanisms (2026-10-14)**: eight proposals in
   `vms-sdl-interfaces.md`, **approved by the user, 2026-10-14**, and
   implemented the same day (its "Part 1 done"). In a `["VMS"]`
   declaration the formal says the mechanism: a value parameter of a
   longword or less by value, a wider one an error; `VAR` and `x-` by
   reference; an open `ARRAY OF CHAR` by a `CLASS_S` descriptor the
   caller builds; `NIL` an omitted argument; a procedure-typed parameter
   checked to be one VMS can call. `rtl/vax/VmsArguments.Mod` has the
   descriptor, item list and I/O status block types. Fixtures
   `vax-vms-calls` (real routines on the guest), `vax-vms-arguments`,
   `semantic-vms-arguments`, `semantic-reject-vms-arguments`.

   **Part 2, the generator (2026-10-14)**: eight proposals, **approved by
   the user, 2026-10-14**, after `SDLDUMP` showed 5.5-2's trees; made the
   same day (`vms-sdl-interfaces.md`, "Part 2 so far"). `tools/sdloberon`,
   an SDL back end in VAX C that `tools/vax-sdl` builds and runs on the
   guest (from `SYS$SHARE`, where the user copies it), writes one Oberon
   module for each SDL `MODULE` node into `rtl/vax/vms`, the library
   `VMSDEF`; in a `["VMS"]` declaration an `x-` `ARRAY OF SYSTEM.BYTE`
   takes any actual. The constants agree with `STARLET.MLB`'s, 3587 names;
   poc's layout of every record type with SDL's. Fixture `vax-vmsdef`.
   The first seven library modules are generated and were **approved by
   the user, 2026-10-15**, with a quadword in declared `x-: HUGEINT`;
   the other 58 were generated the same day ("Part 2 finished"): 243
   Oberon modules from all 65, leaving out DECthreads and `MTH$`'s D, H
   and complex entries. `STARLET.MLB` agrees on 17,559 names of 186
   modules, none differing in value; poc's layout of 225 record types
   agrees with SDL's. On the way: SDL's `ORIGIN`, `SMBMSG`'s module
   renamed `SMBMSGDEF`, and a VAX library's shareable image linked from
   its `.OLB` by `/INCLUDE` (`vax-macro32-backend.md`, section 18.5).

   **Part 3, SDL's unsigned types (2026-10-14)**: seven proposals,
   **approved by the user, 2026-10-14**, and made the same day
   (`vms-sdl-interfaces.md`, "Part 3 done"): an unsigned field or
   parameter is the CARD of its width, and `VmsArguments`' lengths are
   `CARD16`.

   **Part 4, the hand-written modules (2026-10-15)**: seven proposals,
   **approved by the user, 2026-10-15**, and made the same day
   (`vms-sdl-interfaces.md`, "Part 4 done"): `Conditions`,
   `LogicalNames` and `Symbols` in `rtl/vax/vmslib`, the library
   `VMSLIB`, which needs `VMSDEF` and `POCRTL`. Fixture `vax-vmslib`
   runs them on the guest.

   **Part 5, `CLI$` (2026-10-15)**: nine proposals in
   `vax-macro32-backend.md`, section 23, **approved by the user,
   2026-10-15**; the guest's answers are in its 23.4. They cover a `CommandLanguage` module in `VMSLIB` with a
   MACRO-32 part; the table found by a weak reference to
   `POC$COMMAND_TABLE`; dispatch on `$VERB` instead of `CLI$DISPATCH`;
   `-build` taking a `.cld` file; five checks on the guest first; and
   fixtures `vax-cli-verb` and `vax-cli-table`. **Built 2026-10-15**
   (section 23.5), with two changes from the proposals. First, the program
   passes its table's address (the user's choice): the table's symbol is
   declared as an external procedure, and `SYSTEM.VAL(SYSTEM.ADDRESS, T)`
   gives the address, so the module has no MACRO-32 part and works with a
   shared `VMSLIB`. Second, five interface changes were approved by the
   user (`Presence`, more constants, `NoTable` for 0, `Truncated`, any
   number of `.cld` files). `-build` takes `.cld` files (fixture
   `vax-build-command-tables`). `vax-cli-verb` and `vax-cli-table` pass on
   the guest, and the User's Guide's chapter 12 example was run there.

   **Part 6, argument lists through `LIB$CALLG` (2026-10-15)**: five
   proposals in `vms-sdl-interfaces.md`, part 5, **approved by the user,
   2026-10-15**. They are made after "Ongoing language enhancements" item
   3 is merged from `main` with its VAX half. A guest test first compares
   `LIB$SIGNAL` called directly and through `LIB$CALLG`. Then
   `Conditions.SignalList` and `StopList` take a whole argument list:
   several FAO arguments, or chained conditions. The guest test was run
   the same day (part 5, "tried on the guest"): only the PC, the depth
   and a Continue's R0 differ, so proposal 2 stands. `SignalList` and
   `StopList` built the same day ("Part 5 done"); fixture `vax-vmslib`
   runs them.

   **Part 7, RMS's indexed and relative files (2026-10-15)**: six
   proposals in `vms-sdl-interfaces.md`, part 6, **approved by the user,
   2026-10-15**, the first supported-tier group. There is no module: fixture
   `vax-rms-indexed` uses `STARLET` and the `FAB`, `RAB` and `XABKEY` records
   directly, with the XAB header set by `SYSTEM.PUT`. It passes on the
   guest, which showed that two streams in one process lock each other out
   and that duplicates come back in the order they were put ("Part 6
   done").

   **Part 8, `SMG$` screen management (2026-10-16)**: seven proposals in
   `vms-sdl-interfaces.md`, part 7, **approved by the user, 2026-10-16**.
   There is no module: fixture `vax-smg` draws on a pasteboard on a file
   and captures it by `SMG$SNAPSHOT`, and reads a keyboard on a file;
   `SmgScreen` does the same on a terminal, checked by hand. A menu's
   choices are a `CLASS_A` descriptor, which the generator now leaves to
   the program (`VmsArguments.DescribeArray`). The guest showed that a
   pasteboard on a file is 66 by 132, and that a menu is chosen only on a
   terminal ("Part 7 done").

   **Part 9, `SOR$` sorting and merging (2026-10-16)**: eight proposals in
   `vms-sdl-interfaces.md`, part 8, **approved by the user, 2026-10-16**.
   VMSLIB gains `SortMerge`, the constants `SORTSHR` defines and no SDL
   module has, checked against the linker. Fixture `vax-sort` sorts files
   and records, merges, calls a comparison routine of the program's, and
   releases binary records through a descriptor of the program's. The guest
   showed that SORT keeps `Files`' Stream_LF format and that
   `noDuplicates` does not keep the first record ("Part 8 done").

   **Part 10, `STR$`'s decimal arithmetic (2026-10-16)**: eight proposals
   in `vms-sdl-interfaces.md`, part 9, **approved by the user,
   2026-10-16**. VMSLIB gains `DecimalStrings`: numbers of up to 255
   digits, the five routines' arithmetic with their signals returned as
   statuses through `LIB$SIG_TO_RET`, and conversions to and from text.
   Fixture `vax-decimal-strings`. The guest showed that `STR$` writes a
   result right-justified with zeros, that `STR$ROUND`'s places are
   significant digits, and that after `STR$_TRU` a result is not its value
   ("Part 9 done").

   **Part 11, the rest of `LIB$` (2026-10-16)**: eight proposals in
   `vms-sdl-interfaces.md`, part 10, **approved by the user,
   2026-10-16**, with process control a part of its own still to come.
   VMSLIB gains `DateTimes` and `BalancedTrees`, whose nodes are the
   program's records, extended from `LIB$`'s node header, so the collector
   traces them. Fixtures `vax-date-times`, `vax-balanced-trees`,
   `vax-lib-information` (with `LIB$GETQUI`, added by the user's
   amendment) and `vax-interlocked`. The guest showed that
   `LIB$TRAVERSE_TREE` stops at an action's failure, that a refused
   duplicate is never allocated, that `JPI$_USERNAME` comes back
   blank-padded, and that an empty queue gives the header's address
   ("Part 10 done"; `vax-macro32-backend.md`, section 22.8).

   **Part 12, process control (2026-10-16)**: eight proposals in
   `vms-sdl-interfaces.md`, part 11, **approved by the user,
   2026-10-16**. VMSLIB gains `Subprocesses`: `Run` and `Start`, and a
   started subprocess kept alive until `Wait` sees it end, since VMS
   writes its status later. Fixture `vax-subprocesses` also chains two
   programs by `LIB$RUN_PROGRAM` and `LIB$DO_COMMAND`. The guest showed
   that `Wait` gives `SS$_NORMAL` after `Stop`, that a procedure goes on
   after `LIB$DO_COMMAND`'s command, and that a process name has at most
   15 characters, which the fixture's first version broke and hung on
   ("Part 11 done"; `vax-macro32-backend.md`, section 22.9). `LIB$ATTACH`
   is still to be checked by hand.

   **Part 13, the synchronous system services (2026-10-16)**: seven
   proposals in `vms-sdl-interfaces.md`, part 12, **approved by the user,
   2026-10-16**, the first gap of step 8's plan. Fixture
   `vax-system-services` calls `$GETSYIW`, `$GETDVIW`, `$NUMTIM`, `$FAO`
   and `$FAOL`, `$ENQW` and `$DEQ`, `$WAKE`, `$SETPRN` and a mailbox's
   `$CREMBX`, `$QIOW` and `$DASSGN` through `STARLET`; `VmsArguments`
   gains `LockStatusBlock`. All passed on the first run. The guest showed
   that a new resource's value block is valid and zero, that VMS keeps
   no count of wakes, and that it is a `VAXserver 3900` ("Part 12
   done").

6. **Asynchronous system traps and other asynchrony.** VMS systems
   programming leans on them: a service such as `$QIO`, `$SETIMR` or `$ENQ`
   is asked to *complete* asynchronously and to call a routine (an AST)
   when it does, at any point in the program, on the program's own stack,
   with `$SETAST` to enable or disable delivery and `$DCLAST` to queue one.
   What that demands of poc is the point of the step, and it has to be
   worked out and not guessed: (a) an AST routine is an Oberon procedure
   called *by VMS*, with an argument the program chose, so a procedure
   value (Phase 9 step 8) must be callable under the VMS Calling Standard -
   the strongest argument for one calling convention throughout (Phase 16
   step 3b), or else for a declared "AST routine" procedure kind with an
   adapter; (b) the **collector** may be interrupted by an AST that
   allocates or that touches the heap, and an AST frame sits on the stack
   the collector scans, so allocation and collection either run with
   delivery disabled or are proven safe against it - this is the hardest
   part and must be designed before any is written; (c) module
   initialization, `NEW`, and any runtime state that is not reentrant;
   (d) the language-level primitives a program needs to share data with an
   AST safely - interlocked queue and bit-set instructions, event flags
   (`$SETEF`, `$WAITFR`, `$SYNCH`), and whether `SYSTEM` grows an
   AST-safe operation set; (e) condition handlers, exit handlers
   (`$DCLEXH`) and the runtime's own traps (Phase 16 step 3c), which are
   asynchronous in the same sense. The result is a design written into
   this plan, an Oberon-level `VMS` module (or modules) that exposes it
   ($QIO with a completion AST, timers, mailboxes, event flags, condition
   handlers), and fixtures on the guest that fire ASTs while the main
   program allocates heavily - so that the collector's interaction with
   them is tested where it would fail - and that fail if the AST
   delivery rules are wrong.

   **Proposals (2026-10-15)**: nine, in `vax-macro32-backend.md`,
   section 22, from the 5.x manuals and the runtime as it is;
   **approved by the user, 2026-10-15**. In short: an AST routine is a global Oberon
   procedure of type `AsynchronousTraps.Routine`, the calling convention
   needing no adapter; the heap runs with ASTs disabled once a program
   can have them; the rest of the runtime is a documented rule;
   `AsynchronousTraps`, `EventFlags`, `Timers`, `ExitHandlers` and
   handlers in `Conditions`; four questions tried on the guest first.
   **Built 2026-10-15** (section 22.6): the modules, the generator's
   typed AST routines, CTRL/C by `Platform.SetInterruptHandler` (tried by
   hand), and fixtures `vax-asts`, `vax-asts-heap` and
   `vax-conditions-handlers`. Two departures: a handler's arrays are fixed
   arrays, since a `VAR` record takes a hidden tag, and `Timers.After`
   takes no request argument. Also found: a `$EXIT` from an exit handler
   skips the rest, poc's own included.
   **Approved 2026-10-15** (section 22.7): trap 15
   when an AST re-enters the heap in a program that does not import
   `AsynchronousTraps`, so that breaking that rule fails at once, with a
   message, instead of corrupting the heap.

7. **Distributing poc on VAX/VMS.** A release has to give a VMS site
   poc and its libraries. Nine proposals were written 2026-10-15 and
   **approved by the user, 2026-10-15**. The full text is in
   `vax-macro32-backend.md`, section 21.
   - The kit is all text, since an FTP binary copy lands as fixed
     512-byte records. It is made on the host by `make vax-kit` and holds:
     - poc's V1 `.mar` files;
     - `POCRTL`, `VMSDEF` and `VMSLIB`, as `-library` writes them for
       `-O2` and `-OC`;
     - poc's source.
   - It is one self-unpacking DCL procedure, `POC-<version>.COM`, with a
     `CREATE` and a `DECK/DOLLARS` for each file.
   - `BUILD.COM` assembles and links `POC.EXE` into `[.BIN]` and builds
     the libraries into `[.LIB.POC]`, where poc finds them by itself.
     `SETUP.COM` defines the `POC` command and one size model's library
     names.
   - `make dist` puts the kit in the tarball as `vax/`, and the GitHub
     release carries it as an asset, once `vax` is merged.
   - **The packages, once `vax` is merged** (decided with the user,
     2026-10-16). Few want VAX/VMS, so it is an optional package, not a
     second compiler:
     - The Unix packages keep one `poc`, with the VAX code generator built
       in. It is about a quarter of poc's objects (0.65 of 2.8 MB) and
       needs no tool on Unix.
     - What the VAX target needs besides goes in an optional
       `peaseblossom-vax` package, or `make install-vax` from source:
       `rtl/vax` (2.8 MB, VMSDEF's 65 modules 2.3 MB of it), VMSLIB, the
       kit, and **a VAX/VMS guide of its own**, apart from the User's and
       Reference Guides (the user). `doc/vax-vms-guide.md`, its outline
       reviewed 2026-10-16: the front matter and chapters 1-5 and 7 are
       written and reviewed, their programs in `doc/examples/vax`
       (2026-10-16). Chapters 6 and 8-17, the appendices, and its checks
       (`doc-vax-guide`, `make doc`, `install-vax`, the kit's text copy)
       are to come. The User's Guide's chapter 12 shrinks to a pointer
       once chapter 10 has taken its `GREET` example.
     - Without that package, `poc -target vax-dec-vms` says that the VAX
       runtime is not installed and which package has it.
   - `make check-vax-kit` installs it on the guest and builds programs
     with it; with `-full` it also checks the fixed point.
   - poc for VMS leaves the LLVM back end out, which settles that open
     design question.
     - The module list and the method slots move to the front end.
     - `Poc.Mod`'s LLVM work moves into `LLVMBackEnd`. A second module
       of that name, in `src/driver/no-llvm`, refuses every LLVM option,
       and the import path decides which one a build gets.
     - V1's `.mar` loses about 1.48 MB of its 5.4 MB.
   - A tenth proposal, asked for and approved by the user the same day,
     splits the kit in two: `POC-<version>.COM`, poc and `POCRTL`, and
     `POC-VMS-<version>.COM`, `VMSDEF` and `VMSLIB`, unpacked into the
     same top at once or later. `@BUILD` builds what is not built yet.

8. **Exit gate.** Every module and interface chosen builds into both
   library kinds and passes its fixtures on the guest, the AST fixtures
   pass repeatedly (asynchrony makes a single pass weak evidence), the
   whole VAX conformance suite from Phase 16 is still clean, and step 7's
   kits install and pass `make check-vax-kit` on the guest.

   **Plan, approved by the user, 2026-10-16.** Reading the tree against
   that text found four gaps, closed in this order, each committed on its
   own:
   - **Done (part 13).** **The supported tier's system services**
     without a fixture on the guest: `$GETSYIW`, `$GETDVIW`, `$NUMTIM`, `$FAO` (only `$FAOL` is
     tried), `$ENQW` and `$DEQ`, `$WAKE` and `$SETPRN`. A part 13 of step
     5, proposals first, with one fixture, `vax-system-services`, and no
     module.
   - **Done.** **VMSLIB from its shareable image.** Every library build
     makes both kinds, but every VMSLIB fixture linked against the object
     libraries, and a shareable image has its own copy of the writable
     data that `Subprocesses`, `ExitHandlers`, `AsynchronousTraps` and
     `BalancedTrees` keep. Fixture `vax-vmslib-shareable`: one program
     using every VMSLIB module, its subprocess and exit handler reachable
     only from VMSLIB's lists across two collections, linked both ways
     under `-O2` and `-OC`; all four runs print the same.
   - **Done.** **The AST fixtures, repeatedly.** `vax_do` takes `VAX_REPEAT=<n>`:
     a fixture that honours it builds once on the guest and runs each
     program n times, compares each later run with the first there
     (`DIFFERENCES`), and prints only a difference, so its
     `guest-run.expected` is unchanged. `make test-vax-asts` (default 20)
     runs `vax-asts`, `vax-asts-heap`, `vax-conditions-handlers` and
     `vax-subprocesses` so; not part of `make check`. `tools/vax-do -p`
     gives the procedure its P1, and the procedure calls itself with
     `/OUTPUT` for each run (`DEVELOPER.md`, section 4). `vax-asts-heap`
     now builds `AstNoImport` before its runs, which moved one line of its
     `guest-run.expected`.
   - **Done.** **The kits.** `make vax-kit` takes VMSLIB by a glob, but
     the kit's `README.TXT` and `README-VMS.TXT` named six of its
     modules, now twelve, and `KitVmsLib` used `Conditions` alone. Both
     READMEs now name all twelve, `README-VMS.TXT` with a line on what
     each covers, and `KitVmsLib` uses every VMSLIB module and prints a
     line for each, which `check-vax-kit` expects.

   Before them, part 12 finished and `LIB$ATTACH` checked by hand (done
   2026-10-16; `vms-sdl-interfaces.md`, "Part 11 done"). Then
   the gate's run: `make check` on the four hosts, `make test-vax-asts`,
   `make test-vax`, `make test-vax-guest-poc`, `make check-vax-kit
   CHECK_VAX_KIT_FLAGS=-full`, and rackhir on the pushed commit.

**Testing summary**: steps 1, 3, 5 and 6 are fixtures run on the guest;
steps 2 and 4 are decisions with written artifacts, verified against the
manuals they cite; step 7 is checked by `make check-vax-kit` on the
guest; step 8 is the gate.

**The exit review** (2026-10-16). The phase's "done", step 8's text,
holds:

- *Every module and interface chosen builds into both library kinds.*
  `POCRTL` (poc's runtime, all of `rtl/llvm`'s interfaces but the
  internal `ModuleTable` and `FileDescriptorOutput`), `VMSDEF` (243
  modules generated from `STARLETSD.TLB`'s 65) and `VMSLIB` (twelve
  hand-written modules) are each built by `-library` as an object
  library and a shareable image, under `-O2` and `-OC`. Each module
  passes its fixtures on the guest: the VAX fixtures went from 65 at
  Phase 16's close to 110. Every VMSLIB fixture links against the
  object libraries; `vax-vmslib-shareable` links one program using all
  twelve against each kind under both size models, and all four runs
  print the same, the writable data a shareable image keeps its own copy
  of included.
- *The AST fixtures pass repeatedly.* `make test-vax-asts` runs
  `vax-asts`, `vax-asts-heap`, `vax-conditions-handlers` and
  `vax-subprocesses` each building once and running every program 20
  times on the guest, each later run compared with the first:
  all four passed (4 minutes). Its first runs found `vax-subprocesses` failing with
  `SS$_EXQUOTA` when a run started before VMS had deleted the last one's
  subprocess (the guest's PRCLM is 2); the fixture now waits for
  `JPI$_PRCCNT` to reach 0.
- *The whole VAX conformance suite from Phase 16 is still clean.* `make
  test-vax` (182 programs, each printing what its LLVM build prints or
  its reviewed `expected-vax-*` says): 331 of 332 passed; the one
  failure, `llvm-entier-trap`'s `-OC` case 5, whose traceback names the
  program section `POC_CODE` rather than the routine, now has a reviewed
  `expected-vax-entiertrap-OC-6.*`, and its fixture passes. `make
  test-vax-guest-poc` (the fixtures' compilations under poc on the
  guest, compared with the host's): all 348 passed, in 84 minutes
  against Phase 16's 35. poc has not slowed: timed on the guest
  compiling the same ten modules, the poc of 2026-10-12 took 32 and 33
  seconds of CPU, this one 34 and 33. What grew is what each program
  item compiles: `Out` now imports `FormattedOutput`, `FormattedText`
  and `RealDigits`, so a hello program is six modules, not three, and
  takes 8.8 seconds of CPU, not 2.2; the items compile 1.5 times the
  lines they did.
- *Step 7's kits install and pass.* `make check-vax-kit
  CHECK_VAX_KIT_FLAGS=-full` installs both kits on the guest as a site
  would: `POC-VMS-<version>.COM` alone first, which must refuse with no
  poc, then `POC-<version>.COM`, `@BUILD` and `@SETUP`, and a program
  against `POCRTL` alone; then the second kit, `VMSDEF` and `VMSLIB`
  built, and `KitVmsLib` (a line from each VMSLIB module) run linked
  from the object libraries under `-O2` and from the shareable images
  under `-OC`. With `-full` the kit's poc also compiles its own source
  and each `.mar` is compared with the kit's: the fixed point.
  Passed, in 33 minutes: `@BUILD` took 49 seconds for the first kit and
  1 minute 52 seconds after the second, and poc compiled itself in 14
  minutes 50 seconds.

Also found while closing the step:

- *The guest's two accounts raced for a lock.* `tools/vax-lock.sh`
  took over a lock whose owner had died by reading its PID, then
  removing it; a run that took the lock between the read and the
  removal lost it, and two runs used one account at once (nine fixtures
  failed together in a gate on 2026-10-16). It now locks with `flock(1)`
  where the host has it, which the kernel releases when its holder dies,
  and otherwise with a directory it never takes over (`DEVELOPER.md`,
  section 4).
- *Five fixtures assumed the account `POC`*, printing its name or home;
  they pin it (`VAX_USER=poc`).
- *`LIB$ATTACH`* was checked by hand in a telnet session: a subprocess
  spawned with `NOWAIT` is refused (`LIB$_ATTREQREF`), since the target
  must be detached from its terminal; one spawned without it, `ATTACH`ed
  back to the program, returns to it (`vms-sdl-interfaces.md`, "Part 11
  done").

**Left open**, for the phases that follow:

- *Merging `vax` into `main`* is the user's call. After it: one `poc`
  with the VAX code generator on Unix, an optional `peaseblossom-vax`
  package (or `make install-vax`) with `rtl/vax`, VMSLIB, the kit and the
  VAX/VMS guide, `poc -target vax-dec-vms` saying which package it needs
  without it, and the kit in `make dist` and the GitHub release (step 7).
- *The VAX/VMS guide* (`doc/vax-vms-guide.md`): the front matter and
  all seventeen chapters and the appendices are written, with their examples checked by
  fixture `doc-vax-guide`, and the User's Guide's chapter 12 is now a
  pointer to it; `make doc` makes it as HTML and PDF, and the
  tarball has them; the rest of its checks
  (`install-vax`, the kit's text copy) are to come.
- *Phase 16's open items* still open: poc's memory on the guest, and real
  constants folded in G_floating on a VAX host. (`-o`'s directory is now
  found by `Directories.NameStart`, so `-o [.BIN]X.EXE` works on VMS.)
- *What the guest showed and the modules leave to the program*: a `$EXIT`
  from an exit handler skips the handlers after it, poc's own included;
  two RMS streams on one file in one process lock each other out; a
  `SMG$` menu is chosen only on a terminal; `SOR$`'s `noDuplicates` does
  not keep the first record. Each is in the section that found it.
- *Left out on purpose*, each for the reason
  `vms-native-library-inventory.md` gives: the privileged and vector
  services, DECdtm, DECdns, DECthreads, `PPL$`, `DTK$`, D and H floating,
  and the utilities with no SDL routines other than `CLI$`.

**Exit gate**: `make check` on atla and `tools/check-hosts` on cymoril,
artos and alerik before each commit (475 fixtures each at the
last, Stage 1 and Stage 2 identical, `check-strict`), with the VAX
fixtures against the guest on atla; `make test-vax-asts`, `make
test-vax`, `make test-vax-guest-poc` and `make check-vax-kit
CHECK_VAX_KIT_FLAGS=-full` on the guest, as above; rackhir at the
close-out, on `cd18f21`: 474 fixtures passed, Stage 1 and Stage 2
identical, `check-strict` (2026-10-16).

## Ongoing language enhancements, during Phase 17

`PLAN.md`'s "Ongoing language enhancements": done while Phase 17 was
current, on `main` and merged into `vax`; moved here at the close-out,
under its number there.

3. **[done] An external procedure's address, by `SYSTEM.VAL`** (proposed
   2026-10-15, **approved by the user, 2026-10-15**). Found while writing Phase
   17's `CommandLanguage` (`vax-macro32-backend.md`, section 23):
   `CLI$DCL_PARSE` wants `LIB$GET_INPUT`'s address, and poc has no way
   to give it. What poc does today (tried, 2026-10-15):
   - A global Oberon procedure's address is already reachable, as
     `SYSTEM.VAL(SYSTEM.ADDRESS, P)`, on both back ends. Its procedure
     value is its entry address: LLVM's function pointer, the VAX's entry
     mask by `MOVAB`. So `SYSTEM.ADR(P)` is not needed for one, and is not
     proposed.
   - An external procedure's name, `["C"]` or `["VMS"]`, is refused in
     every expression, `VAL`'s argument included: "an external procedure
     cannot be used as a procedure value"
     (`SemanticActions.CheckProcedureValue`). The reason holds for a
     value that Oberon may call: such a value is always called with
     Oberon's convention, hidden arguments included, and an external
     takes C's or VMS's. It does not hold for an address, which Oberon
     cannot call.

   The proposals:
   1. **`SYSTEM.VAL(SYSTEM.ADDRESS, E)` takes an external procedure `E`**,
      declared in the module or imported, and gives the address of its
      linkage name. On the VAX that is `G^name`, VMS's "procedure value,
      by reference". On LLVM it is the C function pointer, which also
      serves C callbacks (`qsort`, `atexit`, `signal`). The target must be
      `SYSTEM.ADDRESS` itself.
   2. **Everything else stays refused, with the present message:**
      - `VAL` of an external to any other type, a procedure type above
        all, since that makes a value Oberon would call with the wrong
        convention;
      - an external assigned, passed as an argument, returned, or compared
        with `=` or `#`.

      Nested, type-bound and predeclared procedures stay refused
      everywhere, `VAL` included, as now.
   3. **Unchecked, as `SYSTEM` is.** An address carries no type, so
      handing VMS or C an external that cannot take what it will be passed
      goes wrong at run time. Nothing else checks it. The text says so.
   4. **Not a new extension.** `VAL` is already `SYSTEM`'s unchecked
      conversion, and external procedures are already poc's own.
      `language-extensions.md`'s "External procedures" and `AGENTS.md`'s
      summary of it each gain a sentence. `-strict` rejects it as it
      rejects an external declaration. poc's own source does not use it.
   5. **Both back ends.**
      - LLVM: the address is the function's `ptrtoint`, and the module
        declares the external even when nothing calls it.
      - VAX: `MOVAB` of the linkage name, the external listed in the
        module as a call lists it, as `ProcedureValue` does for an Oberon
        procedure.

      No runtime change.
   6. **Made on `main`, then merged into `vax`** (the user,
      2026-10-15), where `CommandLanguage` uses it. On `main`:
      - the front end, the LLVM back end, the documents and the gate;
      - `llvm-system-val-external`: C's `qsort` sorts an array of
        `SYSTEM.INT32`, given by `VAL` a C comparison from the fixture's C
        part, declared `["C"]`. A second module importing the first checks
        that `VAL(ADDRESS, E)` gives the same address when `E` is named
        from either module;
      - `semantic-reject-system-val-external`: each refusal of
        proposal 2 with its message, and `-strict`.

      `main` has no VAX back end, so the VAX half (`MOVAB` of an
      external's linkage name, listed as external) and a `vax-` MACRO-32
      fixture showing it are made on `vax` after the merge. There too,
      `vax-vms-calls` gains two calls of `LIB$CALLG`, whose `user_procedure` the generator already declares
      `SYSTEM.ADDRESS`. One passes `VAL(ADDRESS, LIB$PUT_OUTPUT)` with an
      argument list holding a descriptor. The other passes `VAL` of an
      Oberon procedure that VMS can call, and checks the status it
      returns.
   7. **What changes in `vax-macro32-backend.md` section 23** (on `vax`).
      Proposal 3 there becomes:
      `ParsePrompting` passes `SYSTEM.VAL(SYSTEM.ADDRESS,
      LIB$GET_INPUT)` for both routines, as CDU's own example does, from
      Oberon. `CommandLanguage.mar` keeps only the weak reference to the
      table and a routine that returns its address. (As built, there is no
      `CommandLanguage.mar`: the program passes the table's address too,
      section 23.5.)

   **Built on `main` (2026-10-15):** `PredeclaredProcedures.CheckVal`
   marks its operand (`addressedProcedure`), `SemanticActions.
   CheckProcedureValue` lets an external through there alone (and
   `-strict` reports it), and `LLVMCodeGenerator.
   GenerateDesignatorValue` gives `@<linkage name>`. Fixtures
   `llvm-system-val-external` and `semantic-reject-system-val-external`.
   `language-extensions.md` ("External procedures", `-strict`), the
   Reference Guide, the User's Guide ("Calling C") and `AGENTS.md` say
   what it is. `make check` passed on atla, cymoril, artos and alerik
   (360 each, the fixed point and `check-strict` included).

   **Merged into `vax` (509cebd), and the VAX half made there
   (2026-10-15):** `VaxCodeGenerator.Designator` takes an external
   `["VMS"]` procedure's name, which the checker allows only in `VAL`,
   and `ProcedureValue` names it `G^` and `.EXTERNAL`, as a call does.
   Fixtures `vax-external-address` (its `.mar` assembled on the guest and
   reviewed by the user) and `vax-vms-calls` (`LIB$CALLG` of
   `LIB$PUT_OUTPUT` and of an Oberon `Sum`, run on the guest).
