# Phase 16 — Running on VAX/VMS: assemble, link, run, and bootstrap poc there

Moved here from `PLAN.md` on 2026-10-12, once the phase was done, with
the exit review written at the close-out. `PLAN.md` keeps the heading,
the goal and a list of the steps. The design behind each step, every
decision with its date, and the facts with their sources in the VMS 5.5
manuals are in `doc/developer/vax-macro32-backend.md`, sections 13-17
(step 2's driver, section 13; step 3, section 14; step 4, section 15;
step 5, section 16; step 6, section 17).

The phase's text in `PLAN.md`, as it stood:

**Goal**: the MACRO-32 Phase 15 writes is assembled, linked and run on
VAX/VMS 5.5-2 (a SIMH-hosted VAX, or real hardware), with just enough
runtime to compile poc itself, and poc - built for VAX/VMS - then compiles
its own source *on* VAX/VMS: the VMS counterpart of Phase 10's
self-hosting. This lifts two limits of earlier phases, which no longer
apply once it starts: the locked-in "linking/running is out of
scope" (Phase 15 stays what it was - hand-reviewed and non-executable -
and this phase is what runs it), and Phase 15's own scope bound to Phase
8's vertical slice, since poc's source uses far more than that.

**Explicit non-goals**: libraries beyond what poc's own source needs
(Phase 17); any VMS other than VAX 5.5-2 - no Alpha, Itanium, or later VAX
release, though nothing should be gratuitously specific to the exact
release; DECnet, DECwindows, layered products. Phase 17 owns shareable
images and the native VMS libraries; this phase links objects and, at
most, object libraries.

1. **A working VAX/VMS environment and a way to drive it.** Partly
   brought forward into Phase 15 (2026-10-05): the development system is a
   SIMH `microvax3900` running VMS 5.5-2H4, and Phase 15 copies `.mar`
   files to it to assemble them. Settle what runs: which SIMH VAX model VMS 5.5-2 boots on, and where the installation
   media and licences come from.
   Confirm on the guest what the base kit provides (`MACRO`, `LINK`,
   `LIBRARY`, `DCL`, the RTLs) and which layered tools poc must not depend
   on. Decide how files cross between the Linux/BSD host and the guest -
   virtual disk image, tape image, `kermit`, `ftp`, a shared mount - and
   how a test is driven and its output captured (a serial or telnet
   console script). Automate that as one host-side command that copies
   sources in, runs a `.COM` procedure, and copies results out, since
   every later step's fixtures depend on it. Recorded in the plan, with
   the choices that were rejected.

   **Record** (2026-10-09):
   - *The system.* SIMH's `microvax3900` (`VAXserver 3900 Series`, a
     KA655) runs VMS `V5.5-2H4`, the later hardware release of 5.5-2,
     on `DUA0:` (system) and `DUA1:` (users, `POC`'s
     `DUA1:[USERS.POC]`), at `192.168.2.20` while SIMH runs on atla.
     It had 64 MB, the KA655's most; the user gave SIMH 256 MB
     (2026-10-09), which VMS uses (`SHOW MEMORY/PHYSICAL`: 524288
     pages). The licences are hobbyist PAKs (`OPENVMS-HOBBYIST`,
     `VAX-VMS`); the user decided they need no further record.
   - *The base kit*, confirmed with `tools/vax-do` (below): `MACRO32`,
     `LINK`, `LIBRARIAN`, `DCL`, the debugger (`DEBUG.EXE`,
     `DEBUGSHR.EXE`), `DIFF`, `SEARCH`, `SORTMERGE`, `BACKUP`, `CONVERT`,
     `ANALYZE/OBJECT` and `/RMS`; in `SYS$LIBRARY` `LIBRTL`, `LIBRTL2`,
     `MTHRTL`, `STARLET.OLB`, `.MLB` and `STARLETSD.TLB`, `LIB.MLB`,
     `IMAGELIB.OLB`. Layered products installed: VAX C 3.2
     (`VAXCRTL`), FORTRAN 5.6, BASIC 3.4, Ada 3.0, MMS 2.6 and UCX 3.1;
     MMK's release notes are there but no `MMK.EXE` in `SYS$SYSTEM`.
     **Decided (the user, 2026-10-09): poc depends on none of the
     layered products** - the guest-side build driver is a `.COM`
     procedure, not MMS (step 5), and the runtime uses only `LIBRTL`,
     `MTHRTL` and system services, not `VAXCRTL` - so that poc runs on a
     VAX with the base kit alone.
   - *Files cross by FTP* (UCX 3.1; active mode, ASCII for text), *and a
     command runs by telnet*, as Phase 15 settled (`doc/developer/
     vax-macro32-backend.md` §11, question 2). Rejected: a virtual disk
     or tape image (SIMH must stop to change it), Kermit (none on the
     guest), a shared mount (NFS needs UCX's server set up, a change to
     the system), `rsh` (`UCX$RSH.EXE` is there, but UCX lists only FTP
     and TELNET as services and ports 512-514 are closed), and a batch
     job watching a directory (kept in reserve).
   - *The host-side command*: `tools/vax-do [-o <dir>] [-get
     <NAME.EXT>]... <proc.com> [<file>...]` copies the procedure and its
     files in, runs `@<PROC>/OUTPUT=VAXDO.LOG`, and copies the log and
     the files named back, deleting its copies on the guest; it holds the
     guest's lock, as `tools/vax-assemble` and `tools/vax-run` do (2-3 s
     a run, most of it FTP and telnet logins). Its output comes back as
     files, never read from a terminal, which a long listing overflows.
   - *Memory*: poc compiling its own source in one process peaks at
     92 MB on x86-64 and 105 MB on 32-bit OpenBSD
     (75 MB of it data), and `POC` may have 10240 pages of paging file
     (5 MB), a working set of 1024 to 2048 pages (0.5 to 1 MB), and a
     process at most `VIRTUALPAGECNT` 139072 pages (68 MB), on what was
     a 64 MB machine. Step 6 cannot run under these. Choices: raise `POC`'s
     `PGFLQUOTA`, `WSQUOTA` and `WSEXTENT` (`AUTHORIZE`) and the system's
     `VIRTUALPAGECNT` (`SYSGEN`) and page file, all privileged changes to
     the guest; give SIMH more memory (SIMH documents an extended
     KA655X with up to 512 MB; whether VMS 5.5-2 uses it is to be
     checked); and make poc need less. **Decided (the user,
     2026-10-09): poc needs less**; the guest is not changed. The user
     then gave SIMH 256 MB (above) and kept the decision: `POC`'s quotas
     and `VIRTUALPAGECNT` stay as they are. One module
     at a time is not enough by itself: compiled alone with `-compile`
     (its imports' `.sym` files made, clang replaced by a stand-in so
     only poc is measured), on 32-bit OpenBSD, `LLVMCodeGenerator` peaks
     at 82 MB, `VaxCodeGenerator` at 59 MB, `SemanticActions` at 45 MB,
     `Lexer` at 13 MB. The collector grows the heap to twice the live
     data after a collection (`GarbageCollectedHeap`, "Heap shape"), so
     the live data is about half of that: what holds it - the syntax
     trees, the symbol tables, the code being written - and how much a
     module's compilation can drop is step 4's and step 6's to find.
     `POC`'s 5 MB of page file is an order of magnitude below the
     largest module's 40 MB or so of live data, so this decision is to
     be revisited if that cannot be closed.

2. **Assemble, link and run hand-written, then generated, code.** Before
   any generated code: a hand-written MACRO-32 "hello" through
   `MACRO`, `LINK` and `RUN`, proving the loop end to end. Then every
   `expected-vax.mar` fixture Phase 15 checked in is assembled and run,
   turning "hand-reviewed" into automated pass/fail wherever the fixture
   is runnable; whatever the assembler rejects is a Phase 15 bug and is
   fixed there. `VaxToolchainDriver.Mod` stops being a stub: it emits the
   `.mar`, drives `MACRO`/`LINK` (locally on the guest, or by the step 1
   command from the host).

   **Record** (2026-10-09):
   - *The hand-written program*, `test/conformance/vax-hello/
     hand-hello.mar`, calls `LIB$PUT_OUTPUT` and is assembled, linked and
     run on the guest by the fixture's `guest-hello.com`, through
     `tools/vax-do`. Its line and `$STATUS` are compared
     (`test/vaxfixture.sh`, `vax_do`).
   - *The Phase 15 fixtures* were already assembled and run before this
     step: all 32 `expected-vax.mar` assemble clean, and the 28 fixtures
     with code to run do so under the debugger, their logs compared
     (`tools/vax-run`). The assembler rejected nothing, so step 2 found no
     Phase 15 bug to fix. A plain `RUN` of each would show only an exit
     status until the runtime has `Out`, so none was added.
   - *The driver*. **Decided (the user, 2026-10-09): on the host, poc
     writes the `.mar` files and a DCL build procedure and runs nothing on
     VMS.** `-target vax-dec-vms -build` writes `<name>.com`, which
     assembles the modules and links `<NAME>.EXE` through an options file
     with poc's runtime, `POCRTL.OBJ` (`rtl/vax/PocRtl.mar`; from
     `POC$RTL:` when that is defined). `-compile` writes `<First>.com`,
     which only assembles. A warning, such as `%LINK-W-MULDEF`, stops
     either. `-library` and `-install-library` stay refused (Phase 17).
     The same procedure serves poc on VMS later (step 6).
     `doc/developer/vax-macro32-backend.md` section 13.
   - *The runtime's first cut*: `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and
     `POC_HMOD` as the debugger stub has them. `POC_TRAP` and `POC_HALT`
     are provisional (they exit with `SS$_ABORT` and `SS$_NORMAL`) until
     step 3c.
   - *Section 5.1's layer 2*, for the modules poc writes in one run: their
     exported symbols share one table, so a collision between two modules
     is an error at the second declaration, in its own file. So are two
     modules whose names differ only in case. Errors found while a module
     is written now name that module's file, not the main module's.
   - *Fixture* `vax-build`: a two-module program built with `-build` and
     `-compile`, its procedures compared with `expected-<name>.com`, then
     run on the guest. Its exit status, `%X00003735`, encodes what it
     computed (a loop, a `HUGEINT` product and quotient, a string
     comparison, an imported variable). Also `-o`, and the refusals: a
     name that is not a VMS image name, `-OC`, the clash, and the case
     collision.

3. **Widening the backend to what poc's own source uses.** Survey poc's own
   source (`src/`) for every construct it needs - pointers and `NEW`,
   records and extension, type-bound procedures, `WITH`/`IS`, open arrays,
   sets, `REAL`/`LONGREAL`, procedure values and procedure-typed
   parameters, strings and `CHAR` arrays, `CASE`, external procedures - and
   bring `VaxCodeGenerator.Mod` to parity with the LLVM backend for those,
   in dependency order, and `SYSTEM.SET64` whether poc's source uses it or
   not (the user, 2026-10-08; only the runtime's `Texts` does, and Phase 15
   left it out of the slice), each with a run-and-diff fixture that is also
   a Phase 9 fixture (the same `.mod`, same expected output, on both
   backends; a fixture that only one passes is a bug). Three things need
   real design, not just porting: (a) **floating point** - VAX
   `REAL`/`LONGREAL` are F_floating and D_floating (or G), not IEEE 754, so
   constant emission, `ConstantEvaluator`'s folding, `MAX`/`MIN` of the
   real types, `ParseReal`/`FormatReal` and the `.sym` round trip, and the
   hardware conversions all change; decide the `LONGREAL` format (D or G)
   from what VMS's own compilers and RTLs default to; (b) **calling
   convention** - internal Oberon procedures versus the VMS Calling
   Standard (`CALLS`/`CALLG`, argument lists, register save masks,
   condition values); Phase 15 says external procedures use the standard
   and ordinary ones poc's own, and this step decides whether the hidden
   tag/length arguments and procedure values keep working that way or
   whether one convention for everything is simpler (Phase 17's AST support
   pulls toward the latter); (c) **traps** - index, NIL, type-guard and
   length failures become VMS conditions or a status exit, and what a poc
   program's exit status looks like to DCL.

   **Record** (closed by the user 2026-10-10: poc's own source is written
   with no refusal):
   - **Decided (the user, 2026-10-09): the VAX takes `-OC` as well as
     `-O2`.** poc's own source needs `-OC` (a 64-bit `LONGINT`) and must
     stay strict, so it can't use `HUGEINT`. Under `-OC` a `LONGINT` is a
     quadword, lowered as a `HUGEINT` is; `-O2` stays the default
     (`VaxTypes.sizeModel`, `VaxTypes.Longword`). The 32 reviewed `.mar`
     files are unchanged. Fixture `vax-size-model-oc` (its
     `expected-vax.mar` reviewed by the user) runs on the guest with
     every check holding.
   - *The survey*: under `-OC`, poc's own source has 22,504 constructs
     the backend refuses, most of them pointers (13,606), records holding
     pointers or passed as `VAR` (4,506) and open arrays (4,340). The
     proposals for each area, for reals (3a), the calling convention (3b)
     and traps (3c), and the order of work are in
     `doc/developer/vax-macro32-backend.md` section 14. **Approved by the
     user, 2026-10-09**, as is `vax-size-model-oc`'s `expected-vax.mar`.
   - Found on the way: Phase 15 had broken the rule that poc's own source
     type-checks under `-O2` (`AGENTS.md`), with five constants past
     `MAX(LONGINT)` in `VaxCodeGenerator`; fixed, and `poc -O2
     -emit-llvm-ir src/driver/Poc.Mod` is clean again. Nothing checks the
     rule automatically.
   - *Open arrays* (section 14 item 1), done 2026-10-09: parameters by
     value and `VAR` with any number of open dimensions, `LEN`, indexing
     with trap 2, `COPY`, comparisons, and assignment to a fixed array
     with trap 9. Fixture `vax-open-arrays` has debugger runs of both traps
     and guest runs under `-O2` and `-OC`; its `expected-vax.mar` was
     reviewed by the user (2026-10-09). Every reviewed `.mar` file is unchanged.
     Survey: 19,443 refusals left, none of them an open array.
   - *A minimal `Out`* (section 14 item 2), done 2026-10-09:
     `rtl/vax/Out.Mod` (`Open`, `Flush`, `Char`, `String`, `Ln`, `Int`,
     `Hex`) over `POC_PUT_LINE` (`LIB$PUT_OUTPUT`), with an exit handler
     for a line left without `Ln`. Fixture `vax-out` runs one source on
     both backends, under `-O2` and `-OC`, against one expected output per
     model. Its `.mar` files were reviewed by the user (2026-10-09). This found the
     voc-built poc's wrong high longword for `MIN(HUGEINT)` (vishap-bugs
     07), now fixed.
   - *Pointers, `NEW` and type descriptors without extension* (section 14
     items 3 and 4), done 2026-10-09: NIL-checked dereference (trap 4),
     `NEW` through `POC_NEW` over `LIB$GET_VM` (an open array's lengths
     checked, trap 7), and LLVM's descriptor layout, every module-level
     record's descriptor global. Fixture `vax-pointers` runs on the
     debugger and, printing with `Out`, on both backends under `-O2` and
     `-OC`. Its `.mar` files, and the three earlier ones that gained
     descriptors (`vax-declarations-only`, `vax-records`, `vax-modules`'
     `VaxModLib`), were reviewed by the user (2026-10-09). Survey: 10,859
     refusals left, most of them extension and the records holding its
     pointers.
   - *Records holding pointers and `VAR` record parameters* (section 14
     item 5), done 2026-10-09: a `VAR` record parameter of an Oberon
     procedure takes its actual's type tag after its address, as on
     LLVM. Fixture `vax-var-records` examines the tags received under the
     debugger and runs one source on both backends. Its `.mar` files, and
     `vax-records`' and `vax-modules`' two, which pass the tag now, were
     reviewed by the user (2026-10-09). Survey: 10,889, unchanged outside
     `VaxCodeGenerator.Mod`, whose new code adds 30.
   - *Extension, `IS`, type guards and `WITH`* (section 14 item 11's next
     step), done 2026-10-09: descriptors with their extension level and
     base types, LLVM's type test, guards (trap 5), `WITH` (trap 6) and
     the record-assignment check (trap 13). Fixture `vax-extension` takes
     each trap under the debugger and runs one source on both backends.
     Its `.mar` files were reviewed by the user (2026-10-09). Survey: 388,
     none of them extension.
   - *Type-bound procedures* (section 14 item 6), done 2026-10-09: each
     record's `ProcTab` below its tag, as on LLVM, and calls through it
     or, when the receiver's type is known exactly or for `v.P^`,
     directly. Fixture `vax-type-bound` takes traps 4 and 5 from receivers
     under the debugger and runs one source on both backends. Its `.mar`
     files were reviewed by the user (2026-10-09). Survey: 388, unchanged,
     poc's source having no type-bound procedures.
   - *Procedure values* (section 14 item 7), done 2026-10-09: a procedure
     value is the longword address of a procedure's entry mask, NIL 0,
     compared as a longword, and a call through one checks it for NIL
     (trap 4) before its arguments, then `CALLG list, (Rn)`. Fixture
     `vax-procedure-values` takes trap 4 from a variable and an element
     under the debugger and runs one source on both backends. Its `.mar`
     files were reviewed by the user (2026-10-09). Survey: 270, none of
     them procedure values.
   - *Nested procedures* (section 14 item 8), done 2026-10-09: lambda
     lifting by reference, as on LLVM - each nested procedure a procedure
     of its own, taking the addresses of the enclosing procedures'
     variables it needs (`NestedProcedures.Analyze`) after its own
     parameters. Fixture `vax-nested` takes traps 4 and 2 in nested
     procedures under the debugger and runs one source on both backends.
     Its `.mar` file was reviewed by the user (2026-10-09). Survey: 263,
     none of them nested procedures.
   - *Reals* (section 14 item 9), done 2026-10-09: `REAL` is F_floating,
     `LONGREAL` G_floating; a constant is decimal text MACRO converts,
     rounding as the VAX does (halfway away from zero); `ENTIER` floors
     and traps (8) past `LONGINT`'s range, with `POC_ENTIERQ` under
     `-OC`, and a `HUGEINT` converts by `POC_QTOG`. Fixture `vax-reals`
     examines the rounding, trap 8 and the divide-by-zero fault under
     the debugger and runs one source on both backends. Its `.mar` file
     was reviewed by the user (2026-10-09). Survey: 78, all `SYSTEM.BYTE`
     parameters.
   - *Traps and `HALT`* (section 14 item 10), done 2026-10-09:
     `PocRtl.mar`'s `POC_TRAP` writes LLVM's message to `SYS$ERROR` and
     exits with `%X10000000 + 8*c + 2`; `POC_HALT` exits with
     `SS$_NORMAL` for 0, else the same; `-trap-location` adds the file
     and the procedure to the call. Fixture `vax-traps` runs one program
     on both backends for each trap and `HALT`, and compares messages and
     statuses. Its `.mar` file, and `vax-range-checks`' again (`CHR`'s
     code), were reviewed by the user (2026-10-09).
   - *`ASSERT`* (section 14 item 11), done 2026-10-09: a branch on the
     condition to trap 10 at the statement, `ASSERT(x, n)`'s *n* + 1 in
     the code's high word for "assertion failed (n)". Fixture `vax-assert`
     runs one program on both backends for each case. Its `.mar` file
     was reviewed by the user (2026-10-09). Survey: 78, unchanged.
   - *`SYSTEM.SET64`* (section 14 item 11), done 2026-10-09: a quadword
     lowered as a `HUGEINT`, each operation on both longwords; `IN` of a
     register pair by `ASHQ` and `BLBC`, `BBC` taking only bits 0..31 of
     a register. Fixture `vax-set64` runs one program on both backends.
     Its `.mar` file was reviewed by the user (2026-10-10). Survey: 78,
     unchanged.
   - *`SYSTEM.BYTE` parameters*, done 2026-10-10: `BYTE` a byte in the
     slice; a `VAR ARRAY OF SYSTEM.BYTE` takes any variable, its length
     the variable's size in bytes. Fixture `vax-byte-params` runs one
     program on both backends. Its `.mar` file was reviewed by the user
     (2026-10-10). Survey: none in poc's own source; the 179 left are
     `rtl/llvm`'s, which step 4 replaces.
   - *Closed* (the user, 2026-10-10). Step 3 ended as section 14 item 11
     said it would: poc's own source is written for the VAX with no
     refusal. Every construct it uses is lowered, each with a fixture run
     on both backends, and every `expected-vax.mar` was reviewed by the
     user.

4. **A minimal VAX runtime, `rtl/vax`.** Only what poc itself needs, as
   ordinary Oberon-2 over a thin MACRO-32/RTL layer wherever possible:
   program start and command-line access; memory from the system
   (`LIB$GET_VM`/`SYS$EXPREG`, to be confirmed); the collector,
   ported (its roots are the machine stack - which grows down on the VAX,
   with the callee-saved registers R2-R11 to be captured - and the
   per-module root tables; the mark phase needs the same type
   descriptors as on LLVM); file I/O for `Files` over RMS (poc reads
   source and writes `.mar`, `.sym` and `.ll`; RMS record files, not
   byte streams, so the choice of record format and how a `Rider` reads it
   is a design point, and the text files must round-trip exactly);
   `Platform` (environment as logical names or symbols, current directory,
   `Chdir`, process id, delete); `Out`. VMS-specific problems the LLVM
   runtime never met, each to be settled here: ODS-2 file names
   (uppercased, 39.39, with `;version`) against the module-name-to-file-name
   mapping `Files.Old(moduleName + ".sym")` assumes, and against
   Oberon module names longer than what fits or differing only in case;
   the directory syntax (`dev:[dir.sub]file.type`) against `-import-path`,
   `-output-dir` and `POC_IMPORT_PATH`, whose separator is the colon VMS
   uses inside device names (logical names and search lists are the
   natural replacement); and the command line, which DCL upcases and
   splits before a program sees it, against `poc -build -o x file.mod`
   (a foreign command with quoted arguments, or a CLD-defined verb -
   decide, and say which) Decided (2026-10-05): poc on VMS matches its options
   without regard to case, so `-BUILD` is `-build`; their names stay
   lowercase (`doc/developer/vax-macro32-backend.md` §10). Module and file
   names given as arguments are still this step's question.

   **Record** (closed by the user 2026-10-10: `POC.EXE` builds on the
   guest and prints `-help`):
   - *The survey and proposals* are in
     `doc/developer/vax-macro32-backend.md` section 15. **Approved by the
     user, 2026-10-10.** poc's source imports `Files`, `Platform`, `Out`,
     `Err` and `Modules`. Checked on the guest: what a foreign command's
     line looks like (`LIB$GET_FOREIGN`), and that `MACRO` and `LINK`
     read Stream_LF files.
   - *`Modules`, `Platform` and `Err`* (2026-10-10) are in `rtl/vax`,
     with the fixtures `vax-command-line`, `vax-platform` and `vax-err`.
     Their `expected-vax.mar` files were reviewed by the user
     (2026-10-10), as were `vax-out`'s, since `Out` now writes through
     `LineOutput`, which it shares with `Err`. Checked on the guest:
     `Unlink` deletes only the highest version.
   - *`Directories`* (2026-10-10; proposal 4, amended with the user):
     `pathSeparator`, `MakePath`, `IsDirectory` and `MakeDirectory`,
     first added to `Platform`, are a module of their own in `rtl/vax`,
     `rtl/llvm` and, for the Stage 0 poc, `rtl/voc`, so that `Platform`
     keeps voc's interface. `src/` names its files and directories
     through it. `vax-platform`'s `expected-vax*.mar` files, redrafted,
     were reviewed by the user (2026-10-10).
   - *The module name check and the default target* (2026-10-10): a VAX
     module's name over 26 characters (which keeps its files within
     ODS-2's 39) is refused before its `.sym` is written; a poc built
     with `tools/build-info <dir> vax-dec-vms` compiles for the VAX by
     default and has no other target.
   - *`Files`* (2026-10-10) is in `rtl/vax`, over RMS: Stream_LF files
     by block I/O, other record formats a record at a time, `Register`
     by `$RENAME` as a new version. The fixture `vax-files` prints the
     same on Linux and on the guest; its `expected-vax.mar` and
     `expected-vax-Files.mar` were reviewed by the user (2026-10-10).
   - *The collector* (2026-10-10) is `rtl/llvm`'s, ported to
     `rtl/vax/GarbageCollectedHeap.Mod` over `LIB$GET_VM`, an entry mask
     for the registers, `$DCLEXH` and the paging file quota left; `NEW`
     calls its `Allocate`, each module with pointer variables registers
     a root table, and the start of a program that calls `NEW` starts
     the collector and saves the stack base. The fixture `vax-collector`
     prints the same on Linux and on the guest. Its `expected-vax.mar`
     and `expected-vax-GarbageCollectedHeap.mar`, and the redrafted
     `expected-vax*.mar` of `vax-extension`, `vax-files`, `vax-nested`,
     `vax-pointers`, `vax-procedure-values`, `vax-traps`,
     `vax-type-bound` and `vax-var-records`, were reviewed by the user
     (2026-10-10).
   - *`POC.EXE`* (2026-10-10): poc's own source, with `rtl/vax`, builds
     into `POC.EXE` with `-build` and, on the guest, prints `-help`. poc
     on VMS now matches its options without regard to case (`-HELP`, as
     DCL passes it), lowercases `-target`'s value, and prints no clang
     line for `-version`. The fixture `vax-poc` builds it and runs it on
     the guest. This is the end the step set itself.
   - *Closed* (the user, 2026-10-10). Step 4 ended as section 15's
     proposal 10 said it would: poc's own source, with `rtl/vax`, builds
     into `POC.EXE` with `-build`, and that image starts and prints
     `-help` on the guest. Left for later steps: splitting VMS names in
     `VaxImagePaths` (`:`, `]`, `>`, `;version`) before poc compiles on
     the guest, the rest of the file-name survey's proposal (Phase 17),
     `SYSTEM.MOVE`, and whether conservative stack scanning keeps too
     much of poc's memory (step 6).

5. **Test harness on VMS.** `make test` gains a VAX target: the
   conformance fixtures poc can run there are copied to the guest, built
   with `MACRO`/`LINK`, run, and their output diffed with the same
   `expected` files; `MMS` (the DEC Module Management System - its manual
   is among the local reference material) or a `.COM` procedure is the
   guest-side build driver, whichever step 1 chose. Fixtures that cannot
   pass on VAX for a good reason (IEEE-specific constants) get a
   VAX-specific `expected` file rather than being skipped silently.

   **Record** (in progress, 2026-10-10):
   - *The survey and proposals* are in
     `doc/developer/vax-macro32-backend.md` section 16. **Approved by
     the user, 2026-10-10**, with Phase 8's `SysWrite` fixtures to write
     with `Out` instead (proposal 5's (a)).
   - *The suite* (2026-10-10, proposals 1-4): `tools/vax-suite` and
     `make test-vax` run `test/vax-suite.list`'s 38 programs on the
     guest, each compared with the LLVM backend's build of it. Its first
     run found four backend faults, fixed, with the fixture
     `vax-widen-and-new`; `llvm-overflow-wrap`'s IEEE results are
     `expected-vax-overflow-*` files. Those files and
     `vax-widen-and-new`'s `expected-vax.mar` were reviewed by the user
     (2026-10-10).
   - *`Modules.GetIntArg` and `Console`* (2026-10-10, proposal 6): in
     `rtl/vax`, with list lines that take poc options and run arguments;
     57 programs, 157 runs. Two backend faults fixed (a `REAL` widened
     in place, `-trap-heap-exhausted`), `rtl/vax`'s `Files` reports a
     file it cannot create at the first `Write`, and the floating faults
     of `llvm-entier-trap` and `llvm-range-checks` and `llvm-files-fail`'s
     file name are `expected-vax-*` files. Those files and the
     `expected-vax*.mar` files of `vax-command-line` and `vax-files`
     that change were reviewed by the user (2026-10-10).
   - *The `SysWrite` fixtures* (2026-10-11, proposal 5): 47 fixtures
     write with `Out` instead, their `expected` unchanged; 82 programs
     join the list, 139 programs and 239 runs, all passing on the guest.
     `MAX(REAL)` and `MAX(LONGREAL)` checks in three fixtures differ
     with the VAX's bounds, as `expected-vax-*.out` files say;
     `llvm-reals` found a front-end fault in folding `REAL` constants,
     fixed on `main` ("Ongoing bug fixing" 7).
   - *`LSH`, `ROT` and `BIT`* (2026-10-11, proposal 7's first part):
     lowered at every width (`POC_ROTQ` for a `HUGEINT` `ROT`), fixture
     `vax-shifts`; it and five more fixtures join the list, 153
     programs and 253 runs, all passing on the guest. VAX rounding of
     `CVTLF` differs from IEEE folding in `llvm-real-constant-folding`,
     as its `expected-vax-realfold.out` says. The user reviewed
     these files and `vax-shifts`' `expected-vax.mar` (2026-10-11).
   - *`MOVE` and `VAL` into a `HUGEINT`* (2026-10-11, proposal 7's
     second part): `MOVE` through the new `POC_MOVE`, as `memmove`;
     fixtures `vax-move` and `vax-val`; with `llvm-system` and
     `llvm-no-trap-behavior` (its case 12 left out) 158 programs and 278
     runs, all passing on the guest. A `REAL` divided by zero and a read
     at address 0 are VMS faults, as `expected-vax-notrap-*` files say;
     the user reviewed them, `POC_MOVE` and both fixtures'
     `expected-vax.mar` (2026-10-11).
   - *Structured constants* (2026-10-11, proposal 7's third part): data
     in `POC_CONST`, laid out as a variable, used as one; fixture
     `vax-structured-constants`; with `llvm-readonly-params` 162
     programs and 282 runs, all passing on the guest. A read-only
     parameter of at most 16 bytes is passed by reference on the VAX,
     by value on LLVM, as `expected-vax-readonly.out` says; the user
     reviewed it and the fixture's `expected-vax.mar` (2026-10-11).
   - *Record field initializers* (2026-10-11, proposal 7's fourth part):
     an initialization procedure per record type, called for variables,
     locals and `NEW`, as on LLVM; fixture `vax-field-initializers`;
     with `llvm-extension-through-pointers` 166 programs and 286 runs,
     all passing on the guest. The user reviewed the fixture's two
     `expected-vax*.mar` files (2026-10-11).
   - *Proposal 7's last fixture* (2026-10-11): `llvm-underscore-dollar`,
     whose imported record type has a field default, runs as it is; 168
     programs and 288 runs. Every construct the survey found unlowered is
     lowered; the 9 fixtures built in steps remain.
   - *The 9 fixtures built in steps* (2026-10-11): `tools/vax-suite`
     builds a main module in a subdirectory from there. The programs of
     `llvm-trap-location`, `llvm-gc-compiled-roots`, `llvm-using-modules`
     and `semantic-strict-compiled-imports` join the list; what those
     test of the LLVM driver stays theirs, and `llvm-module-keys`,
     `llvm-object-reuse`, `poc-opt-level`, `poc-exit-status` and
     `poc-output-streams` test only the LLVM driver or poc itself (step
     6). Found and fixed: a source import's procedure locals were held to
     the importer's `-strict` (both backends; fixed on `main` too), and
     the VAX's trap 9 named the value's column, not the assignment's.
     178 programs, 328 runs: step 5's list is complete.
   - *Closed* (the user, 2026-10-11, going on to step 6).

6. **Bootstrap on VAX/VMS.** poc for VAX/VMS is built in stages. **V1**:
   the host's `poc` cross-compiles poc's own source to `.mar`; assembled
   and linked on the guest, it is a VAX `poc.exe`. **V2**: that `poc.exe`,
   run *on VMS*, compiles poc's own source to `.mar`, which must be
   byte-identical to V1's (modulo paths and version numbers) - the
   fixed-point test, a text diff of the two `.mar` sets. **V3**: the
   `poc.exe` assembled from V2's `.mar` compiles the source again, again
   identical. The whole conformance suite then passes under the V2/V3
   compiler. `tools/bootstrap` gains the corresponding scripts.

   **Record** (in progress, 2026-10-11; `doc/developer/
   vax-macro32-backend.md` section 17):
   - *The first runs*: `POC.EXE` on the guest found two backend faults,
     fixed (a wide element at offset 0 of a `VAR` parameter, fixture
     `vax-deferred-wide`; a quadword sum into a destination its operand
     may overlap, which broke every mangled name's hash). It then
     compiles `hello` and poc's `Lexer` on VMS to `.mar` byte-identical
     to the host's.
   - *Memory*: `VaxCodeGenerator`, and all of poc, exhaust the heap at
     about 3.6 MB, three quarters of `POC`'s paging file quota; the host
     needs 63 MB and 112 MB. **Decided (the user, 2026-10-11): the
     guest's limits are raised** (`POC`'s `PGFLQUOTA` and working set,
     `VIRTUALPAGECNT`, the paging file, SIMH's memory), reversing step
     1's decision. Making poc need less (measuring what holds its
     memory, compiling module by module against `.sym` files, leaving
     the LLVM backend out of the VMS image) is later work.
   - *Real constants on a VAX host*: poc folds them in its own
     `LONGREAL`, `G_floating` on the VAX, which cannot hold IEEE's
     largest. **Decided (the user, 2026-10-11): fold in `G_floating`**;
     `MAX`/`MIN` of `REAL`/`LONGREAL` are the VAX's own largest
     (`ConstantEvaluator.vaxHost`). IEEE folding in software is later
     work.
   - *V2* (2026-10-12): `POC.EXE` compiled all of poc on VMS in 45.7
     minutes (90 MB peak); its 31 `.mar` are byte-identical to V1's.
     A current `POC.EXE` is kept in `DUA1:[USERS.POC.BIN]`.
   - *V3* (2026-10-12): the chain on the guest, V1's image making V2's
     and V2's compiling poc again: V3's 31 `.mar` are byte-identical to
     V2's and V1's.
   - *The scripts* (2026-10-12): `tools/bootstrap/vax-v1` cross-compiles
     V1 on the host; `tools/bootstrap/vax-stages` runs the chain on the
     guest with one procedure and compares V2's and V3's `.mar` with
     V1's (`make vax-v1`, `make vax-stages`; not part of `make check`).
     Its first full run: V2 45.7 minutes, V3 46.0, all identical.
   - *The suite under the VMS-built compiler* (2026-10-12; proposals
     approved by the user): `tools/vax-guest-poc` (`make
     test-vax-guest-poc`) runs 344 fixtures' compilations under poc on
     the guest and compares what it prints, its status and its files
     with the host's poc for the VAX. It found two faults, fixed: a
     register moved on one path of an `&` or `OR` (fixture
     `vax-short-circuit-call`) and `MAX(LONGREAL)` overflowing in
     `FormatReal` on the VAX. All 344 pass: a fixture's source over
     ODS-2's 39 characters was renamed, and `llvm-real-constant-
     folding`'s 2 builds differ as their reviewed
     `expected-vax-guest-realfold-*.diff` say.

**Testing summary**: step 2's fixtures and step 3's shared fixtures
are compile+assemble+link+run+diff on the guest; step 6's fixed point is
the phase's exit gate, the way Stage 1/Stage 2 was Phase 10's.

**The exit review** (2026-10-12). The phase's "done" holds:

- *Running.* poc's output assembles, links and runs on the guest:
  `tools/vax-suite` (`make test-vax`) builds 182 programs of the
  conformance suite for the VAX (step 5's 178, and step 6's
  `vax-deferred-wide` and `vax-short-circuit-call` under both size
  models) and runs each there, every run printing what the LLVM build
  prints, or what its reviewed `expected-vax-*` file says the VAX must print. The 65 `vax-*`
  fixtures' `expected-vax.mar`, reviewed by the user, assemble on the
  guest, and those with runs run there.
- *The bootstrap.* poc built for VAX/VMS compiles its own source on
  VMS: V1's 31 `.mar` (the host's poc cross-compiling), V2's (V1's
  image on VMS) and V3's (V2's image) are byte-identical, the phase's
  exit gate. `tools/bootstrap/vax-stages` (`make vax-stages`) runs the
  chain and compares, in about 90 minutes.
- *The suite under the compiler built on VMS.* `tools/vax-guest-poc`
  (`make test-vax-guest-poc`) runs 344 fixtures' compilations under
  poc on the guest - the programs, the `vax_mar` lines and the `-check`
  fixtures - and compares what it prints, its status and its files with
  the host's poc for the VAX: all 344 pass.

**Left open**, for the phases that follow:

- *poc's memory.* poc compiling itself on the guest peaks at 90 MB of
  virtual memory; the guest's limits were raised for it (the user,
  2026-10-11). Making poc need less - measuring what holds its memory,
  compiling module by module against `.sym` files, leaving the LLVM
  backend out of the VMS image - is later work.
- *Real constants on a VAX host* are folded in G_floating (the user,
  2026-10-11): one beyond its range traps instead of being reported,
  and a halfway case can fold differently from IEEE 754's
  (`llvm-real-constant-folding`'s `expected-vax-guest-realfold-*.diff`).
  IEEE folding in software on every host is later work.
- *VMS file names in poc's own paths.* `-o`'s directory is still split
  at `/` only (`Poc.VaxImagePaths`), so `-o [.BIN]X.EXE` on VMS does not
  name a directory; the rest of the file-name survey's proposal is
  Phase 17's, as are `-library` and `-install-library` on the VAX.
- *The guest itself.* On 2026-10-12 VMS bugchecked (`SSRVEXCEPT` in the
  `UCX` process) under the suites' FTP and telnet load, and SIMH, set to
  stop on a HALT and to exit after `boot`, vanished with it. The dump
  was too small to read, since `SYSDUMP.DMP` was sized for 64 MB; the
  user has since enlarged it. The cause is unknown.

**Exit gate**: `make check` on atla and `tools/check-hosts` on cymoril,
artos and alerik before each commit (417 fixtures each at the last,
Stage 1 and Stage 2 identical, `check-strict`), with the VAX fixtures
against the guest on atla; rackhir at the close-out, on `35ce679`:
passed (417 fixtures, Stage 1 and Stage 2 identical, `check-strict`).

## Ongoing bug fixing, during Phase 16

`PLAN.md`'s "Ongoing bug fixing": fixed while Phase 16 was current, on
`main` and merged into `vax`; moved here at the close-out, under its
number there.

7. **[fixed] A `REAL` constant expression folded in double precision**
   (found 2026-10-11 running `llvm-reals` on the VAX, Phase 16 step 5).
   `ConstantEvaluator` kept a `REAL` numeral's double value and computed
   `REAL` operations and relations in double precision, while `SHORT`
   rounded to single: `CONST b = SHORT(0.1D0) = 0.1` and `0.1 + 0.2 =
   0.3` folded to `FALSE`, where the same on `REAL` variables is `TRUE`.
   The LLVM backend reached it only in a `CONST`; the VAX backend, which
   folds an `IF`'s condition, printed `llvm-reals`' "FAIL 27". Now a
   `REAL` operand is its single value (a numeral rounded once, from its
   text), an integer in a `REAL` operation is converted to `REAL`, and
   each `REAL` result, and `ENTIER` and `LONG` of a `REAL`, take the
   single value. Fixture `llvm-real-constant-folding`.
