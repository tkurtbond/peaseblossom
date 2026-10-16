# Native VAX/VMS libraries: an inventory

`PLAN.md` Phase 17 step 4 (2026-10-14): which of VMS 5.5-2's own
libraries a poc program gets an Oberon interface to. The step covers the
run-time library families, the system services, RMS and condition
handling. For each family this file says three things:
- what the family is for;
- whether it is worth an interface;
- what the interface costs.

It then lists the proposals, what is left out and why. Step 5 builds the
interfaces chosen here, step 6 the asynchronous parts, and step 8 is the
gate.

## Sources and method

Every fact here comes from a manual for VMS 5.5 or an earlier 5.x
release, checked against the 5.5 and 5.5-2 release notes
(`vax-vms-manuals-to-get.md`). Nothing is from memory.

| Family | Manual | Release |
|---|---|---|
| System services | *VMS System Services Reference Manual* (`AA-LA69B`), *Introduction to VMS System Services* (`AA-LA68B`) | 5.5 |
| `LIB$` | *VMS RTL Library (LIB$) Manual* (`AA-LA76A`) | 5.0 |
| `STR$` | *VMS RTL String Manipulation (STR$) Manual* (`AA-LA75A`) | 5.0 |
| `OTS$` | *VMS RTL General Purpose (OTS$) Manual* (`AA-LA73A`) | 5.0 |
| `MTH$` | *VMS RTL Mathematics (MTH$) Manual* (`AA-LA72B`) | 5.4 |
| `SMG$` | *VMS RTL Screen Management (SMG$) Manual* (`AA-LA77A`) | 5.0 |
| RMS | *VMS Record Management Services Manual* (`AA-LA83A`) | 5.0 |
| `$QIO` by device | *VMS I/O User's Reference Manual*, Part I (`AA-LA84B`) and Part II (`AA-LA85A`) | 5.4, 5.0 |
| Callable utilities (`CLI$`, `LBR$`, `SOR$`, `MAIL$`, ...) | *VMS Utility Routines Manual* (`AA-LA67B`) | 5.4 |
| `CLI$` tables | *VMS Command Definition Utility Manual* (`AA-LA60A`) | 5.0 |
| Messages | *VMS Message Utility Manual* (`AA-LA63A`) | 5.0 |
| The facility list | *Introduction to the VMS Run-Time Library* (`AA-LA70A`), *VMS 5.5 Programming Master Index* (`AA-LA56C`), *Overview of VMS Documentation* (`AA-LA95D`) | 5.0, 5.5 |
| Changes | 5.5 release notes (`AA-LB22D`), 5.5 new features (`AA-LA97D`), 5.5-2 release notes (`AV-PQZAB`) | 5.5, 5.5-2 |

The routine-by-routine catalogs were made from the manuals' text
layers. Each one's count was checked against its manual's table of
contents. They are not committed: they run to 8,000 lines, and the
manuals are the record. The counts and facts used below are theirs.

What the guest has comes from `DIRECTORY` and `LIBRARY/LIST` of
`SYS$LIBRARY:STARLETSD.TLB`, run on 2026-10-11
(`doc/developer/vms-sdl-interfaces.md`).

Two missing manuals matter here. The `DTK$` manual (`AA-LA71A`) and the
`PPL$` manual (`AA-LA74B`) are not held. The proposals do not need them,
since both families are left out (proposal 6).

## What VMS 5.5-2 gives

### The seven run-time library facilities

The 5.0 RTL Introduction (Table 1-1) and the 5.5 master index name the
same seven facilities. Callable utilities that are not RTL facilities
follow in the next section.

| Facility | For | Routines |
|---|---|---|
| `LIB$` | General: system information, CLI access, symbols and logical names, strings and descriptors, dates and times, condition handling, virtual memory and zones, interlocked queues, balanced trees, file search, conversions, `LIB$TPARSE` | 154 entries, 158 entry points with `LIB$SYS_TRNLOG` (5.5 release notes 4.20) |
| `STR$` | Strings by descriptor, and arithmetic on decimal strings | 32 |
| `OTS$` | Support for compiled code: conversions, `POW`, complex arithmetic, string copy | 42 entries, 56 entry points |
| `MTH$` | Mathematics in F, D, G and H, complex, vector, and the FORTRAN intrinsics | 84 entries: 137 scalar entry points, 97 intrinsics, 110 vector |
| `SMG$` | Screen management: pasteboards, virtual displays, virtual keyboards, menus, terminal-independent input | 117 |
| `DTK$` | The DECtalk speech device | 21 |
| `PPL$` | Parallel processing: subprocesses sharing memory, barriers, events, semaphores, spin locks | 29 in 5.0, more in 5.4 and 5.5 |

### The callable utilities

These are documented in the Utility Routines manual, and each lives in a
shareable image of its own.
- `CLI$`: a program's own command line, parsed by DCL against a command
  table.
- `CONV$`: CONVERT.
- `DCX$`: data compression.
- `EDT$` and `TPU$`: the editors, as callable routines.
- `FDL$`: files from File Definition Language.
- `LBR$`: libraries, help text included.
- `MAIL$`: new in 5.4.
- `NCS$`: national character sets.
- `PSM$` and `SMB$`: print symbionts.
- `SOR$`: sort and merge.
- `ACLEDIT$`: the ACL editor.

Elsewhere:
- `PTD$`, pseudoterminals, is in the I/O manual's Appendix C.
- DECthreads (`CMA`), new in 5.5, has C include files only (5.5 release
  notes 3.9), and its manual is not held.

### The system services

There are 141 names in the 5.5 reference. 14 of them are the W (wait)
forms, so 127 operations. They fall into the Introduction's groups:

| Group | Names |
|---|---|
| Security | 23 |
| Event flags | 9 |
| ASTs | 3 |
| Logical names and DECdns | 6 |
| Input and output | 30 |
| Process control | 16 |
| Process information | 3 |
| Timers and time | 7 |
| Condition handling | 3 |
| Memory management | 17 |
| Change mode | 3 |
| Lock management | 5 |
| DECdtm | 6 |
| In no group (`$FILESCAN`, `$GETUAI`, `$SETUAI`, the four vector services, `SYS$RMSRUNDWN`, `SYS$SETDDIR`, `SYS$SETDFPROT`) | 10 |

Across them:
- 26 take an item list: 25 the 12-byte `item_list_3`, and `$FILESCAN` the
  8-byte `item_list_2`.
- 29 can complete by AST.
- 38 take an event flag, and 24 an I/O status block.
- 17 need a privilege that an ordinary user such as `POC` lacks for any
  use. These are `$CMKRNL`, `$CMEXEC`, `$GRANTID`, `$REVOKID`,
  `$SETIME`, `$SNDERR`, `$LCKPAG`, `$ULKPAG`, `$SETSWM`, the seven that
  write the rights database, and `$SETUAI`. About 35 more need one for
  some uses only, such as acting on another process.
- The 5.5-2 release notes add or remove no service. They change
  `$ADJWSL`'s `wsetlm` to a longword and limit `$CREMBX`'s `bufquo`.

### RMS

RMS has 28 services: `$OPEN`, `$CREATE`, `$GET`, `$PUT`, `$FIND`,
`$UPDATE`, `$DELETE`, `$READ`, `$WRITE`, `$PARSE`, `$SEARCH`, `$RENAME`,
`$ERASE`, and the rest. They act on control blocks:
- `FAB`, `RAB` and `NAM`;
- eleven `XAB` types, of which `XABJNL` and `XABRU` belong to RMS
  Journaling.

RMS keeps files in three organizations: sequential, relative and
indexed. Their records are fixed, variable, VFC, stream, Stream_LF,
Stream_CR or undefined.

Two facts shape what an interface costs:
- **The manual gives each field only by name and size, never by
  offset.** It warns that displacements "may not always be the same from
  release to release". The offsets exist only in the system's
  definitions: `STARLET.MLB` for MACRO, and `RMSDEF`/`RMSUSR` in
  `STARLETSD.TLB`.
- **The blocks have unions** (`KBF`/`PBF`, `STV0`/`STV2`), three-word
  fields (`RFA`, `FID`, `DID`) and option bits.

Since 5.0, RMS has gained more `XABITM` items (5.1 and 5.4). Since 5.4 it
honours asynchronous operation on process-permanent files.

`Files` and `Platform` already use RMS for sequential stream files
(`vax-macro32-backend.md`, sections 19.1 and 19.3). Relative and indexed
files, keys and record locking have no Oberon interface.

### What `STARLETSD.TLB` describes

The guest's `SYS$LIBRARY:STARLETSD.TLB` (5.5-2H4 kit, 9-JUL-1993) holds
65 SDL modules:
- `STARLET`: the system services.
- `STARDEFAE`, `STARDEFFL`, `STARDEFMP`, `STARDEFQZ`: every `$xxxDEF`,
  constants and structures, in four alphabetical parts.
- `RMSDEF`, `RMSUSR`: RMS's control blocks and services.
- `LIB$ROUTINES`, `STR$ROUTINES`, `OTS$ROUTINES`, `MTH$ROUTINES`,
  `SMG$ROUTINES`, `SOR$ROUTINES`, `NCS$ROUTINES`, `PPL$ROUTINES`,
  `DTK$ROUTINES`: the routines of those facilities, with each argument's
  mechanism.
- `LIBCLIDEF`, `LIBCQDEF`, `LIBDCFDEF`, `LIBDTDEF`, `LIBVMDEF`,
  `SMGDEF`, `SMGTRMPTR`, `PPL$DEF`, `DTKDEF`, `LBRUSR`, `CONVDEF`,
  `OPCDEF`, `SCRDEF`, `SRMDEF`, `VAXDEF`: those facilities' constants and
  structures.
- `OBJFMT`, `DSTDEF`, `OPDEF`, `CRF`: the object language, the debug
  symbol table, the opcodes and cross-reference.
- `CMA`: DECthreads.
- 29 `*MSG` modules of status codes: `SSMSG`, `RMSFALMSG`, `LIBMSG`,
  `SMGMSG`, `CLIMSG`, `MAILMSG`, and the rest.

There is **no SDL routine module for `CLI$`, `LBR$`, `CONV$`, `FDL$`,
`MAIL$`, `EDT$`, `TPU$`, `DCX$`, `PSM$`, `SMB$` or `ACLEDIT$`**. Only
their constants and messages are there. Step 5's generator
(`vms-sdl-interfaces.md`, decided 2026-10-11) can only write what SDL
describes, so an interface to one of these is declared by hand.

## What an interface costs

An interface to most of what VMS has needs the same few mechanisms. Their
cost is paid once, in step 5 (or step 6), not once per library. What
each family costs is the set of mechanisms it uses that poc lacks today:

| Mechanism | poc today | Who needs it |
|---|---|---|
| Value of 4 bytes or less, `VAR` by reference | yes (`vax-macro32-backend.md`, section 7) | everything |
| String by descriptor, `CLASS_S`, in or out | no: an error | nearly every `SYS$`, `LIB$`, `STR$`, `SMG$` routine with text |
| Dynamic string, `CLASS_D` | no | `LIB$SGET1_DD`, `SFREE1_DD`, `SFREEN_DD`, `STR$GET1_DX`, `FREE1_DX`, three `OTS$`. Every other output takes `CLASS_S`: the routine writes by the class it is given (STR$ manual 2.2, Table 2-3) |
| Optional arguments (0 for omitted) | no | most system services, many `LIB$` and `SMG$` routines |
| `item_list_3` | no | 25 services (`$GETQUI` among them), every `MAIL$` routine |
| I/O status block | as a `VAR` record or array, yes | 24 services |
| Record laid out with no alignment | no: poc aligns a field to its size (`vax-macro32-backend.md`, section 4) | RMS's blocks, the `$xxxDEF` structures |
| Union, bit field | no | RMS, `$xxxDEF`. SDL also gives each bit's `$V_`, `$S_` and `$M_` |
| Variable argument list | no | `LIB$SIGNAL`, `LIB$STOP`, `$FAO`, `$PUTMSG`'s vector |
| Synchronous callback | **yes, in substance**: an Oberon procedure is called by `CALLS`/`CALLG` with an entry mask, arguments at `4(AP)`, and a procedure value is the mask's address (`vax-macro32-backend.md`, section 14, item 7) | `LIB$` (15 routines, e.g. `LIB$TRAVERSE_TREE`), `SOR$`'s comparison, `LBR$`'s index walks |
| AST routine, condition handler | no: step 6 | the 29 AST-completing services, `LIB$ESTABLISH`, `SMG$`'s five AST routines, RMS's completion routines |
| `D_floating`, `H_floating` result through a hidden first argument | no type for either | `MTH$`'s D and H, `OTS$`'s D and H, complex |
| JSB entry (`_Rn`) | no | 6 `LIB$` and 13 `STR$` routines, which also have CALL entries |
| A symbol's value from the linker | no | a program's own message codes (MESSAGE utility, "How a program uses the symbols") |
| Bound procedure value (entry and environment in R1) | no | `EDT$`, `TPU$` |

Two conditions apply to a synchronous callback:
- poc must check that a procedure passed to VMS has only parameters that
  VMS passes: longwords by value, and non-record `VAR`s. A `VAR` record
  parameter carries a hidden tag, and an open array a dope vector.
- The collector must find its roots past the VMS routine's frames
  between the callback and the caller.

## Proposals

**Approved by the user, 2026-10-14**, all seven as written.

1. **Two layers.** The library interfaces come in two layers, plus a
   third kind for the utilities SDL lacks.
   - **Generated modules**: one for each of `STARLETSD.TLB`'s SDL
     modules, by step 5's generator. Each is a faithful transcription:
     the system's names, SDL's mechanisms, constants and structures.
     Making forty modules costs about the same as making one, since the
     work is in the generator and in the mechanisms above.
   - **Hand-written Oberon modules**, few and small, only where the raw
     interface is clumsy in Oberon and the need is common (proposal 4).
   - **Hand-declared interfaces**: `["VMS"]` declarations written by hand,
     the same in kind as generated ones, for the chosen utilities that
     SDL does not describe (proposal 5).

2. **Generate every one of the 65 SDL modules.** A module whose entries
   need a mechanism poc lacks gets those entries left out, each with a
   comment saying why, and the rest are written. A module that is all
   constants and structures costs nothing at run time, so there is no
   reason to choose among them:
   - `OBJFMT`, `DSTDEF` and `OPDEF` may serve Phase 18, which writes
     object files.
   - The language RTLs' messages (`BASMSG`, `COBMSG`, `FORMSG`) are
     harmless.

   **"Generated" is not "supported".** Only proposal 3's tier gets
   fixtures on the guest.

3. **The supported tier.** Each item here has fixtures on the guest that
   call the real routine and check its result (`PLAN.md` step 5):
   - **System services, synchronous forms:**
     - Logical names: `$TRNLNM`, `$CRELNM`, `$DELLNM`.
     - Information by item list: `$GETJPIW`, `$GETSYIW`, `$GETDVIW`.
     - Time: `$GETTIM`, `$BINTIM`, `$ASCTIM`, `$NUMTIM`.
     - Messages: `$GETMSG`, `$FAO`.
     - I/O on a channel: `$ASSIGN`, `$QIOW`, `$DASSGN`, `$CREMBX`.
     - Event flags, set, cleared, read and waited on: `$SETEF`, `$CLREF`,
       `$READEF`, `$WAITFR`.
     - Locks, wait form: `$ENQW`, `$DEQ`.
     - Process: `$HIBER`, `$WAKE`, `$SETPRN`.

     Their asynchronous forms, `$SETIMR` with an AST, and the rest of
     what step 6 lists, are step 6's.
     - **Done** (2026-10-16; `vms-sdl-interfaces.md`, part 12). Logical
       names, `$GETJPIW`, `$BINTIM`, `$ASCTIM`, `$GETMSG`, `$FAOL` and
       the event flags were called by earlier fixtures; fixture
       `vax-system-services` calls the rest through `STARLET`, with
       `VmsArguments.LockStatusBlock` for the locks, and `$FAO` through
       a declaration with a fixed number of parameters, since the
       generator leaves it out.
   - **RMS:** the services and `FAB`, `RAB`, `NAM` and the `XAB`s, used
     synchronously.
     - The point is what `Files` cannot do: relative and indexed files,
       keyed access, `$FIND` and `$UPDATE`, record locking.
     - A fixture creates an indexed file, puts records, reads them back
       by key, and updates one.
     - Asynchronous RMS (`RAB$V_ASY`, completion ASTs) is step 6's.
     - **Done** (2026-10-15; `vms-sdl-interfaces.md`, part 6): fixture
       `vax-rms-indexed`, an indexed and a relative file through the
       generated declarations, with no module over them. Left out:
       `XABALL` areas, `XABPRO`, journaling, asynchronous RMS.
   - **`LIB$`:**
     - Symbols and logical names: `LIB$SET_SYMBOL`, `LIB$DELETE_SYMBOL`,
       `LIB$SET_LOGICAL`, `LIB$DELETE_LOGICAL`.
     - Information: `LIB$GETJPI`, `LIB$GETSYI`, `LIB$GETDVI` and
       `LIB$GETQUI` (added 2026-10-16), each one item to a longword or a
       string, with no item list.
     - Dates and times: `LIB$DATE_TIME`, `LIB$FORMAT_DATE_TIME` and its
       context routines, `LIB$CVT_TO_INTERNAL_TIME`, `LIB$ADD_TIMES`,
       `LIB$SUB_TIMES`, `LIB$DAY_OF_WEEK`.
     - Event flags: `LIB$GET_EF`, `LIB$FREE_EF`.
     - Balanced trees, as the synchronous callback's fixture:
       `LIB$INSERT_TREE`, `LIB$LOOKUP_TREE`, `LIB$TRAVERSE_TREE`.
     - The interlocked queue and bit routines (`LIB$INSQHI` ...
       `LIB$REMQTI`, `LIB$BBSSI`, `LIB$BBCCI`, `LIB$ADAWI`), which step 6
       needs for data shared with an AST.
     - The condition routines (`LIB$ESTABLISH`, `LIB$REVERT`,
       `LIB$SIGNAL`, `LIB$STOP`, `LIB$MATCH_COND`, `LIB$SIG_TO_RET`) are
       step 6's.
     - **Done** (2026-10-16; `vms-sdl-interfaces.md`, part 10). Symbols
       and logical names were done by part 4 (VMSLIB's `Symbols` and
       `LogicalNames`), event flags and the condition routines by step 6
       (`EventFlags`, `Conditions`). Part 10 added:
       - VMSLIB's `DateTimes` and fixture `vax-date-times`;
       - VMSLIB's `BalancedTrees`, trees of the program's records that the
         collector sees, and fixture `vax-balanced-trees`;
       - fixture `vax-lib-information` (`LIB$GETJPI`, `GETSYI`, `GETDVI`,
         `GETQUI`) and fixture `vax-interlocked` (the queue and bit
         routines), both
         through the generated declarations.

       Left out: file search, dynamic loading, zones, timers and
       conversions.
     - **Process control done** (2026-10-16; `vms-sdl-interfaces.md`,
       part 11): VMSLIB's `Subprocesses` over `LIB$SPAWN`, which keeps
       a subprocess not waited for alive until `Wait` sees it end, and
       fixture `vax-subprocesses`, with `LIB$DO_COMMAND`,
       `LIB$RUN_PROGRAM`, `LIB$PUT_COMMON` and `LIB$GET_COMMON` through
       the generated declarations. `LIB$ATTACH` is checked by hand.
   - **`SMG$`:**
     - What a full-screen program uses: pasteboards, virtual displays,
       virtual keyboards, writing with renditions, reading keys and
       strings, menus.
     - A fixture creates a pasteboard on a file, not a terminal, draws
       displays on it, and writes the screen to the file by
       `SMG$SNAPSHOT`, which writes "the current pasteboard buffer to the
       file or hardcopy terminal" (SMG-367). The fixture checks the
       lines.
     - A telnet session checked by hand, as `VT100`'s was
       (`vax-macro32-backend.md`, section 19.18), shows the screen.
     - `SMG$`'s AST routines (unsolicited input, broadcast trapping, out
       of band) are step 6's.
     - **Done** (2026-10-16; `vms-sdl-interfaces.md`, part 7): fixture
       `vax-smg`, a pasteboard on a file captured by `SMG$SNAPSHOT` and
       a keyboard on a file, through the generated declarations, with no
       module over them; `SmgScreen`, the same on a terminal, checked by
       hand. A menu's choices are a `CLASS_A` descriptor
       (`VmsArguments.DescribeArray`). Left out: the AST routines,
       viewports, subprocesses, key definition tables, the terminal table
       routines, `SMG$PRINT_PASTEBOARD`.
   - **`SOR$`**, sorting files: `SOR$PASS_FILES` and `SOR$SORT_MERGE`,
     with a fixture that sorts a file by a key. Its record interface,
     with a comparison routine of the program's, follows once proposal
     4's callbacks are checked.
     - **Done** (2026-10-16; `vms-sdl-interfaces.md`, part 8): fixture
       `vax-sort`, file and record interfaces, a merge, a comparison routine
       of the program's, and binary keys through a descriptor of the
       program's; VMSLIB's `SortMerge` holds the constants `SORTSHR`
       defines, checked against the linker. Left out: specification files,
       `SOR$DTYPE` and other collating sequences, tag, address and index
       sorts, `user_equal`, the merge's record interface, work files.
   - **`STR$`**, the decimal-string arithmetic only, the one part that
     Oberon and `Strings` lack: `STR$ADD`, `STR$MUL`, `STR$DIVIDE`,
     `STR$RECIP`, `STR$ROUND`. One fixture.
     - **Done** (2026-10-16; `vms-sdl-interfaces.md`, part 9): VMSLIB's
       `DecimalStrings`, numbers of up to 255 digits with text
       conversions, its signals returned as statuses through
       `LIB$SIG_TO_RET`; fixture `vax-decimal-strings`. Left out: the
       rest of `STR$`, which `Strings` covers.
   - **`OTS$` and `MTH$`**: generated, and not supported beyond what
     `Math`, `MathL` and the runtime already call. Their F and G
     functions are what `Math` and `MathL` use
     (`vax-macro32-backend.md`, section 19.16). Their D,
     H, complex and vector entries need types poc lacks.

4. **Hand-written Oberon modules: three.** Each wraps a generated
   interface:
   - **`Conditions`**: a condition value's parts and its text.
     - `Success(status)`, `Severity(status)`, `Facility(status)` and
       `Message(status, VAR text)`, the last by `$GETMSG`.
     - `Signal` and `Stop` with no arguments or one, by `LIB$SIGNAL` and
       `LIB$STOP`. A fixed number of arguments each, so they need no
       variable argument list.
     - Every program that calls VMS tests statuses, and the bits of one
       are clumsy in Oberon (`SET` and `SYSTEM.VAL`).
   - **`LogicalNames`**: define, deassign and translate, in a named table
     and access mode. `Platform.GetEnv` only translates, in
     `LNM$FILE_DEV`.
   - **`Symbols`**: get, set and delete a DCL symbol, local or global, by
     `LIB$GET_SYMBOL`, `LIB$SET_SYMBOL` and `LIB$DELETE_SYMBOL`.

   Item lists, descriptors and IOSBs are not modules here. They are the
   types step 5 makes for the language (`PLAN.md` step 5: "a way to hold
   a string descriptor and an item list"). `$QIO` with an AST, timers,
   mailboxes and condition handlers are step 6's `VMS` module, as
   `PLAN.md` already says.

5. **Hand-declared utilities: `CLI$` alone.**
   - `CLI$DCL_PARSE`, `CLI$PRESENT`, `CLI$GET_VALUE` and `CLI$DISPATCH`
     let a program take DCL's qualifiers and parameters, as every VMS
     utility does.
   - The program's command table comes from `SET COMMAND/OBJECT` and is
     linked in. `poc -build`'s procedure lists the objects in an options
     file (`vax-macro32-backend.md`, section 13), and has no way yet to
     add one more. That way is part of this proposal's work.
   - One fact must be checked on the guest first. CDU says that a
     foreign command parses its own line. Whether `LIB$GET_FOREIGN`'s
     line, given to `CLI$DCL_PARSE` with a linked table, then works is
     not stated in any manual held. If it does not, a program is run as
     a verb defined by `SET COMMAND`, which CDU recommends.
   - `CLIMSG`'s codes come from the generator.
   - **Done** (2026-10-15; `vax-macro32-backend.md`, section 23):
     `CommandLanguage` in `VMSLIB`, and `poc -build` takes `.cld` files.
     A foreign command can parse its own line (`ParseForeign`). Left
     out: `CLI$DISPATCH`, since a program dispatches on `GetVerb`, and
     Oberon procedures as `CLI$DCL_PARSE`'s prompting routines, which
     are `LIB$GET_INPUT`'s.

6. **Left out, and why.** None of these gets an interface or a fixture in
   Phase 17. Each can come later if a program needs it:
   - **Privileged services.** These are the 17 that need a privilege
     `POC` lacks: `$CMKRNL`, `$CMEXEC`, the rights-database writers,
     `$SETUAI`, `$SETIME`, `$LCKPAG`, `$ULKPAG`, `$SETSWM`, `$SNDERR`,
     `$GRANTID`, `$REVOKID`. Also `$ADJSTK`, which "the VMS operating
     system uses". They are generated, since `STARLET` has them, but
     nothing tests them.
   - **The vector services.** The MicroVAX 3900 has no vector unit. So
     are `MTH$`'s vector routines (BLAS1).
   - **DECdtm (`$START_TRANS` ...), DECdns (`$DNS`) and DECthreads
     (`CMA`).**
     - DECdtm needs a transaction log on the node (5.5 release notes
       3.10.5), and DECdns a name server; the guest has neither.
     - DECthreads is C only in 5.5, its manual is not held, and threads
       would interrupt the collector in a way no step plans for.
   - **`PPL$`**: it shares memory between processes, so the collector's
     heap would need sharing too. Its manual is not held.
   - **`DTK$`**: the DECtalk hardware, which nothing here has.
   - **`NCS$`**: national character sets, which an ASCII Oberon program
     has no use for yet. Generated only.
   - **D_floating, H_floating and complex** (`MTH$`, `OTS$`, `LIB$EMODD`
     and `EMODH`, `POLYD` and `POLYH`): poc has no types for them.
     `LONGREAL` is G (`vax-macro32-backend.md`, section 14, item 9). The generator writes their
     values as 8 or 16 bytes (`vms-sdl-interfaces.md`), so a declaration
     exists but nothing computes with it.
   - **Dynamic strings (`CLASS_D`)**: an output written into a fixed
     `CLASS_S` buffer, with its resultant length, serves every routine
     that does not *require* `CLASS_D`. The few that do only allocate and
     free dynamic strings, which the collector does instead.
   - **JSB entries**: every one has a CALL entry too.
   - **`LIB$TPARSE`**: its state tables are built by MACRO macros.
     **`LIB$CRF_*`**: cross-reference listings for a language processor.
   - **`EDT$` and `TPU$`**: their callbacks are bound procedure values,
     with an environment in R1, which Oberon's procedure values are not
     (`vax-macro32-backend.md`, section 14, item 7). Their manuals are not held either.
   - **`PSM$`, `SMB$`**: print symbionts, which run in the queue
     manager's context.
   - **`LBR$`, `CONV$`, `FDL$`, `MAIL$`, `DCX$`, `ACLEDIT$`, `PTD$`**:
     useful, but nothing planned needs them. Each would be declared by
     hand, having no SDL routine module, and the `CONV$` and `MAIL$`
     manuals are not held. `FDL$` would be the first to add, since it
     makes an indexed file from a description, beside RMS (proposal 3).
   - **A program's own message codes** (MESSAGE utility). Their values
     are fixed by the linker as global absolute symbols, which a `CONST`
     cannot hold, so the VAX backend would need a reference to an
     absolute symbol. The system's codes (`SS$_`, `RMS$_`, `LIB$_` ...)
     are ordinary constants from the generator.

7. **Order of work in step 5:**
   1. The mechanisms of the cost table: descriptors, optional arguments,
      item lists, unaligned records, and the callback check.
   2. The generator, starting with the constant modules (`SSMSG` and the
      other `*MSG` modules, then `STARDEF*`), which need none of those
      mechanisms.
   3. `STARLET` and proposal 3's services.
   4. RMS.
   5. `LIB$`, then proposal 4's three modules.
   6. `SMG$`, `SOR$`, `STR$`'s decimal arithmetic.
   7. `CLI$`.

   Each module is §19-style: proposals, then approval, then the work, as
   step 3's were.
