# Modules on VAX/VMS: an inventory

`PLAN.md` Phase 17 step 2 (2026-10-12): which existing Oberon modules
poc supports on VAX/VMS. This file sorts each module by what it needs from
VMS, then lists the proposals. Two sets of modules are covered. The first
is poc's own runtime, `rtl/llvm`, whose interfaces are voc's and
Oakwood's (Phase 10, Phase 12 steps 4-5). The second is the 129 modules of
voc's libraries, from Phase 12's inventory
(`doc/research/voc-module-inventory.md`). Steps 3 to 7 build on what is
decided here.

## Sources and method

- What VMS 5.5-2 supplies comes from these sources:
  - the VMS 5.5 Software Product Description (`AE-PT7JA`);
  - the 5.5 and 5.5-2 release notes (`AA-LB22D`, `AV-PQZAB`);
  - the 5.4 MTH$ manual (`AA-LA72B`), whose 5.5 edition we do not have;
  - the guest, VMS 5.5-2H4: `DIRECTORY` of `SYS$SHARE` and
    `SYS$LIBRARY`, 2026-10-12.
- For `rtl/llvm`, each module's exported procedures were compared with
  `rtl/vax`'s module of the same name, if there is one. Each module was
  then compiled with `poc -target vax-dec-vms -emit-macro32`, with
  `rtl/vax` before `rtl/llvm` on the import path, to see what the VAX
  backend accepts today.
- For voc's library modules, these facts come from voc's sources through
  `tools/voc-inventory`'s `voc_sources.py`:
  - each module's import closure;
  - inline C and Xlib;
  - `SYSTEM.VAL`, `GET`, `PUT`, `ADR` or `MOVE` in a module that also
    uses `REAL` or `LONGREAL`.

  Each module flagged by these tests was then read. That reading
  corrected the following:
  - `ulmSYSTEM`'s `SYSTEM` operations are on characters, not reals.
  - `ethRandomNumbers` takes a `SET` apart, not a real, so it gets its
    "VAX reals" only through its imports.
  - `Printer` prints through `Platform.System` and `lpr`.
  - `oocRts`, `oocFiles` and `oocFilenames` build Unix paths with
    `"/"`, and `oocRts` also reads `HOME`.

  The table's last column is Phase 12's check: whether poc accepts the
  module at all, independent of the target.

## What VMS 5.5-2 gives, and what it does not

- **The run-time libraries are part of VMS**: `LIB$`, `STR$`, `MTH$`,
  `OTS$` and `SMG$`, in shareable images (SPD, "Run-Time Library").
  `MTH$` has each function for F, D, G and H floating. For example,
  `MTH$SQRT` is F and `MTH$GSQRT` is G (MTH$ manual, `MTH$xSQRT`). The
  CALL entry points take their arguments by reference and return the
  result in `R0` or `R0`/`R1` (section 1.2). An error is signalled, for
  example `MTH$_LOGZERNEG`, and a reserved operand faults.
- **The VAX C run-time library comes with VMS, as shareable images**.
  The 5.5-2 release notes fix it in their own section 3.12, which covers
  `atof`, `ceil`/`floor`, `qsort` and the math functions. On the guest,
  `SYS$SHARE:VAXCRTL.EXE` and `VAXCRTLG.EXE` (its G_floating variant)
  are dated 8-JUL-1992, as `MTHRTL.EXE` is. The object libraries
  `VAXCRTL.OLB` and `VAXCRTLG.OLB` are dated 2024: they were installed
  with the VAX C compiler, a layered product. So a program can link the C
  run-time library's shareable image on any VMS 5.5-2 system, but it
  cannot link the object library without VAX C. poc refuses `["C"]` for
  the VAX: calling a C routine is a `["VMS"]` declaration, with whatever
  mechanisms step 5 decides.
- **No zlib and no X11.** DECwindows is a separate product, and the
  project's non-goals leave it out.
- **Reals are not IEEE 754.** On the VAX, `REAL` is F_floating and
  `LONGREAL` is G_floating (`doc/developer/vax-macro32-backend.md`,
  section 14, item 9). They have no infinities, no NaNs and no
  subnormals. A negative zero is the reserved operand, which faults when
  used. The ranges differ from IEEE's:
  - F_floating runs from 2^-128 to just under 2^127;
  - G_floating runs from 2^-1024 to just under 2^1023;
  - IEEE single runs to just under 2^128, and IEEE double to just under
    2^1024.

  The fraction is stored as 0.1f, not 1.f, in 16-bit words whose order
  swaps the halves of each longword. A G_floating number with exponent
  field e has the value of an IEEE double with exponent field e - 2, and
  the same fraction bits once they are in IEEE order.
- **File names (ODS-2)** have up to 39 characters, a dot, up to 39 more
  and a version. They use letters, digits, `$`, `_` and `-`, and case
  is ignored. Every module file name in voc's libraries is at most 31
  characters, and no two of them differ only in case. Module file names
  are therefore not a problem. A path a module builds itself is a
  problem: see `oocRts`, `oocFiles` and `oocFilenames` below.

## poc's runtime on VMS

The module order follows the imports. *rtl/vax* is what `rtl/vax` (in
`POCRTL`) has today. *VAX backend* is the result of compiling
`rtl/llvm`'s module for the VAX. *Needs* says what the module needs on
VMS.

| Module | rtl/vax | VAX backend | Needs |
|---|---|---|---|
| `GarbageCollectedHeap` | whole interface | (own) | nothing more |
| `Console`, `Directories` | whole interface | (own) | nothing more |
| `LineOutput` | VAX only | - | under `Out`, `Err`, `Console` |
| `FileDescriptorOutput` | not used | `["C"]` `write`, `isatty` | nothing: `LineOutput` takes its place |
| `Platform` | 4 of 46 (`GetEnv`, `System`, `Unlink`, `Exit`) | (own) | a VMS answer for 42 procedures: files by handle (RMS block I/O, as `Files` uses), file identity (device and file ID) and times (`XAB$C_DAT`), the error tests mapped from RMS status codes, the clock (`$GETTIM`, `$NUMTIM`), `Delay` (`$SCHDWK` and `$HIBER`), `Chdir` (`$SETDDIR`), `OSAllocate`/`OSFree` (`LIB$GET_VM`), `Rename` (`LIB$RENAME_FILE`). The signal handlers (`SetInterruptHandler` and the others) are condition handlers or a Ctrl-C AST, which wait for step 6 |
| `Files` | 13 of 37 | (own) | the typed riders, `ReadBytes`/`WriteBytes`, `Rename`, `GetDate`, `GetName`, `Pos`, `Purge`, `ChangeDirectory` and `SetSearchPath` (directories as `Directories` writes them). The typed riders keep Oakwood's external format, IEEE and little-endian (proposal 4) |
| `ModuleTable` | not used (`POC_ROOTS`) | compiles | only under `Modules`' list of modules |
| `Modules` | 4 of 9 (the command line) | (own) | the list of modules, commands (`ThisMod`, `ThisCommand`, `Free`), `Halt`, `AssertFail`, `ArgVector`. The VAX backend must write module descriptors and their commands, as the LLVM backend does (Phase 12 step 5e) |
| `RealDigits` | - | compiles, but takes the bits as IEEE's | F_floating and G_floating taken apart (the exponent bias and word order above). Then `Out.Real` and the rest print correctly rounded digits, as on LLVM |
| `FormattedText`, `FormattedOutput`, `OutStr` | - | `FormattedText` and `OutStr` compile; `FormattedOutput` stops at `FileDescriptorOutput` | `FormattedOutput` over `LineOutput` |
| `Out`, `Err` | 7 of 10 | (own) | `Real`, `LongReal`, `Ten`, `IsConsole` (`$GETDVI`, terminal or not). A part-line `Flush` to a terminal without ending the record, for `VT100` (proposal 6) |
| `Reals` | - | `["C"]` `strtof`, `strtod` | `Ten`/`TenL` and `Expo`/`SetExpo` for F and G. `Convert*` from `RealDigits`. Decimal input by poc's own conversion (proposal 3) |
| `Strings` | - | `["C"]` `strtod` | `StrToReal`/`StrToLongReal` by poc's own conversion. The rest is plain Oberon |
| `FormattedInput`, `In`, `InStr` | - | `["C"]` `getchar`, `strtod` | reading `SYS$INPUT` a record at a time, the record's end read as a line's end (a `LineInput` beside `LineOutput`). Reals by poc's own conversion |
| `Math`, `MathL` | - | `["C"]` libm | over `MTH$`: the F routines for `Math`, the G ones for `MathL` (`MTH$SQRT`/`MTH$GSQRT`, `MTH$SIN`/`MTH$GSIN`, ...). voc's error codes and `ErrorHandler` are kept, with `MTH$`'s signalled errors mapped to them by a condition handler (proposal 5) |
| `Args` | - | needs `Platform.getEnv`, `Modules.ArgVector` | nothing more once `Platform` and `Modules` are complete |
| `VT100` | - | compiles | output that reaches the terminal without a line end (`Out`, above). VT100 and later DEC terminals take the escape sequences as they are |
| `Texts`, `Oberon` | - | need the rest of `Files` and `Modules` | nothing more once `Files`, `Modules` and `Reals` are complete. `Texts`' file format is bytes, which block I/O keeps |

Of Oakwood's eight basic modules (Phase 10), `In`, `Out`, `Files`,
`Math`, `MathL` and `Strings` are rows above. `XYplane` and `Input` stay
out on VMS, as on LLVM (Phase 10's non-goals).

## voc's library modules on VMS

*On VMS* is one of the following:

- **runtime**: the module needs only poc's runtime modules, named in
  *Why*. Once step 3 has put them on VMS, it is portable as far as VMS
  is concerned.
- **VAX reals**: the module, or a module it imports, takes a `REAL` or
  `LONGREAL` apart as IEEE 754 or writes IEEE constants as bit patterns.
  It needs a version for F_floating and G_floating. OOC's `oocLowReal`
  and `oocLowLReal` are the root of most of these rows.
- **system-specific**: the module, or a module it imports, was written for
  a particular system. Examples: Ulm's library over Unix system calls
  (`ulmSYSTEM`, `ulmSys`) and its compiler's sizes (`ulmTypes`), the m68k
  coprocessor, a C data model, `lpr`, Unix paths.
- **C**: the module needs inline C, libc through `oocwrapperlibc`, or
  Xlib.

| | Modules |
|---|---|
| runtime | 51 |
| VAX reals | 17 |
| system-specific | 55 (all 54 of `ulm` but `ulmASCII`, `ulmDisciplines` and `ulmObjects`; also `oocC`, `Printer`, `oocRts`, `oocFiles`, `oocFilenames`) |
| C | 6 |

| Module | Library | On VMS | Why | poc accepts it (Phase 12) |
|---|---|---|---|---|
| `crt` | misc | runtime | poc's `Out`, `Platform`, `Reals`, `Strings`, `VT100` | accepted |
| `Listen` | misc | runtime | nothing of the system | accepted |
| `MersenneTwister` | misc | VAX reals | through `oocLRealMath`, `oocLowLReal`, `oocLowReal` | accepted |
| `MultiArrayRiders` | misc | runtime | poc's `Console`, `Platform` | accepted |
| `MultiArrays` | misc | runtime | poc's `Console`, `Platform` | accepted |
| `oocAscii` | ooc | runtime | nothing of the system | accepted |
| `oocBinaryRider` | ooc | VAX reals | takes reals apart, or IEEE constants as bits | no (through oocChannel) |
| `oocC` | ooc | system-specific | a C data model | accepted |
| `oocChannel` | ooc | runtime | poc's `Platform` | no (function procedure must return a value) |
| `oocCharClass` | ooc | runtime | nothing of the system | accepted |
| `oocComplexMath` | ooc | VAX reals | through `oocLowReal`, `oocRealMath` | accepted |
| `oocConvTypes` | ooc | runtime | nothing of the system | accepted |
| `oocFilenames` | ooc | system-specific | Unix paths | accepted |
| `oocFiles` | ooc | system-specific | Unix paths | no (through oocChannel) |
| `oocFilesHost` | ooc | runtime | poc's `Platform` | accepted |
| `oocIntConv` | ooc | runtime | nothing of the system | accepted |
| `oocIntStr` | ooc | runtime | nothing of the system | accepted |
| `oocJulianDay` | ooc | runtime | nothing of the system | accepted |
| `oocLComplexMath` | ooc | VAX reals | through `oocLRealMath`, `oocLowLReal`, `oocLowReal` | accepted |
| `oocLongInts` | ooc | runtime | nothing of the system | accepted |
| `oocLowLReal` | ooc | VAX reals | takes reals apart, or IEEE constants as bits | accepted |
| `oocLowReal` | ooc | VAX reals | takes reals apart, or IEEE constants as bits | accepted |
| `oocLRealConv` | ooc | VAX reals | through `oocLowLReal`, `oocLowReal` | accepted |
| `oocLRealMath` | ooc | VAX reals | takes reals apart, or IEEE constants as bits | accepted |
| `oocLRealStr` | ooc | VAX reals | through `oocLowLReal`, `oocLowReal` | accepted |
| `oocMsg` | ooc | runtime | nothing of the system | accepted |
| `oocOakMath` | ooc | VAX reals | through `oocLowReal`, `oocRealMath` | accepted |
| `oocOakStrings` | ooc | runtime | nothing of the system | accepted |
| `oocProgramArgs` | ooc | runtime | poc's `Modules`, `Platform` | no (through Heap oocChannel) |
| `oocProgramArgsHost` | ooc | runtime | poc's `Modules`, `Platform` | accepted |
| `oocRandomNumbers` | ooc | runtime | nothing of the system | accepted |
| `oocRealConv` | ooc | VAX reals | through `oocLowReal` | accepted |
| `oocRealMath` | ooc | VAX reals | takes reals apart, or IEEE constants as bits | accepted |
| `oocRealStr` | ooc | VAX reals | through `oocLRealMath`, `oocLowLReal`, `oocLowReal` | accepted |
| `oocRts` | ooc | system-specific | Unix paths, `HOME` | accepted |
| `oocStrings` | ooc | runtime | nothing of the system | accepted |
| `oocStrings2` | ooc | runtime | nothing of the system | accepted |
| `oocSysClock` | ooc | runtime | poc's `Platform` | accepted |
| `oocTextRider` | ooc | VAX reals | through `oocLRealMath`, `oocLowLReal`, `oocLowReal` | no (through oocChannel) |
| `oocTime` | ooc | runtime | poc's `Platform` | accepted |
| `oocwrapperlibc` | ooc | C | libc | not checked (voc does not build it) |
| `ooc2Ascii` | ooc2 | runtime | nothing of the system | accepted |
| `ooc2CharClass` | ooc2 | runtime | nothing of the system | accepted |
| `ooc2ConvTypes` | ooc2 | runtime | nothing of the system | accepted |
| `ooc2IntConv` | ooc2 | runtime | nothing of the system | accepted |
| `ooc2IntStr` | ooc2 | runtime | nothing of the system | accepted |
| `ooc2LRealConv` | ooc2 | C | through `oocwrapperlibc` | no (through oocwrapperlibc) |
| `ooc2Real0` | ooc2 | runtime | nothing of the system | accepted |
| `ooc2Strings` | ooc2 | runtime | nothing of the system | accepted |
| `oocX11` | oocX11 | C | Xlib | no (inline C) |
| `oocXutil` | oocX11 | C | Xlib | no (inline C) |
| `oocXYplane` | oocX11 | C | Xlib | no (inline C) |
| `powStrings` | pow | runtime | nothing of the system | accepted |
| `ethBase64` | s3 | runtime | poc's `Files`, `Modules`, `Oberon`, `Out`, `Platform`, `Reals`, `Strings`, `Texts` | accepted |
| `ethBTrees` | s3 | runtime | poc's `Files`, `Out`, `Platform`, `Reals`, `Strings` | accepted |
| `ethDates` | s3 | runtime | poc's `Files`, `Modules`, `Out`, `Platform`, `Reals`, `Strings`, `Texts` | accepted |
| `ethGZReaders` | s3 | runtime | poc's `Files`, `Out`, `Platform`, `Reals`, `Strings` | accepted |
| `ethGZWriters` | s3 | runtime | poc's `Files`, `Out`, `Platform`, `Reals`, `Strings` | no (through Heap ethZlibDeflate) |
| `ethMD5` | s3 | runtime | nothing of the system | accepted |
| `ethRandomNumbers` | s3 | VAX reals | through `oocLowReal`, `oocRealMath` | accepted |
| `ethReals` | s3 | VAX reals | takes reals apart, or IEEE constants as bits | accepted |
| `ethSets` | s3 | runtime | poc's `Files`, `Modules`, `Out`, `Platform`, `Reals`, `Strings`, `Texts` | accepted |
| `ethStrings` | s3 | VAX reals | through `ethReals` | accepted |
| `ethUnicode` | s3 | runtime | nothing of the system | accepted |
| `ethZip` | s3 | runtime | poc's `Files`, `Out`, `Platform`, `Reals`, `Strings` | no (through Heap ethZlibDeflate) |
| `ethZlib` | s3 | runtime | nothing of the system | accepted |
| `ethZlibBuffers` | s3 | runtime | nothing of the system | accepted |
| `ethZlibDeflate` | s3 | runtime | nothing of the system | no (LONG(CHAR) (voc; poc: use ORD)) |
| `ethZlibInflate` | s3 | runtime | nothing of the system | accepted |
| `ethZlibReaders` | s3 | runtime | poc's `Files`, `Out`, `Platform`, `Reals`, `Strings` | accepted |
| `ethZlibWriters` | s3 | runtime | poc's `Files`, `Out`, `Platform`, `Reals`, `Strings` | no (through Heap ethZlibDeflate) |
| `ulmASCII` | ulm | runtime | nothing of the system | accepted |
| `ulmAssertions` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmAsymmetricCiphers` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmBlockCiphers` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmCipherOps` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmCiphers` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmClocks` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmConclusions` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmConditions` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmConstStrings` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmDisciplines` | ulm | runtime | nothing of the system | accepted |
| `ulmErrors` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmEvents` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmForwarders` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmIEEE` | ulm | system-specific | i386 IEEE 754 | accepted |
| `ulmIndirectDisciplines` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmIntOperations` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmIO` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmLoader` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmMC68881` | ulm | system-specific | the m68k coprocessor | no (through ulmTypes) |
| `ulmNetIO` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmObjects` | ulm | runtime | nothing of the system | accepted |
| `ulmOperations` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmPersistentDisciplines` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmPersistentObjects` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmPlotters` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmPrint` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmPriorities` | ulm | system-specific | through `ulmTypes` | no (through ulmTypes) |
| `ulmProcess` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmRandomGenerators` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmReals` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmTypes` | no (through ulmTypes) |
| `ulmRelatedEvents` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmResources` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmScales` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmServices` | ulm | system-specific | through `ulmTypes` | no (through ulmTypes) |
| `ulmSets` | ulm | system-specific | through `ulmTypes` | no (through ulmTypes) |
| `ulmStreamConditions` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmStreamDisciplines` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmStreams` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmStrings` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmSys` | ulm | system-specific | Linux i386 system calls | accepted |
| `ulmSysConversions` | ulm | system-specific | C structure layouts | no (through ulmSYSTEM ulmTypes) |
| `ulmSysErrors` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmSysIO` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmSysTypes` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmSysStat` | ulm | C | `stat` | no (inline C) |
| `ulmSYSTEM` | ulm | system-specific | Unix system calls | no (function with an empty body (voc accepts; the report does not)) |
| `ulmSysTypes` | ulm | system-specific | C structure layouts | no (through ulmTypes) |
| `ulmTCrypt` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `ulmTexts` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmTimeConditions` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmTimers` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmTimes` | ulm | system-specific | through `ulmSYSTEM`, `ulmSys`, `ulmTypes` | no (through ulmSYSTEM ulmTypes) |
| `ulmTypes` | ulm | system-specific | Ulm compiler sizes, m68k and sparc | no (POINTER [1] TO (voc untraced pointer; poc: use SYSTEM.ADDRESS)) |
| `ulmWrite` | ulm | system-specific | through `ulmIEEE`, `ulmMC68881`, `ulmSYSTEM` ... | no (through ulmSYSTEM ulmTypes) |
| `Args` | v4 | runtime | poc's `Modules`, `Platform` | poc has its own |
| `Console` | v4 | runtime | poc's `Platform` | poc has its own |
| `Printer` | v4 | system-specific | PostScript through `lpr` | accepted |
| `Sets` | v4 | runtime | poc's `Files`, `Modules`, `Out`, `Platform`, `Reals`, `Strings`, `Texts` | accepted |

## Proposals

**Approved by the user, 2026-10-12**, all six as written.

1. **Step 3 is poc's runtime: all of `rtl/llvm`'s interfaces, on VMS, in
   `POCRTL`.** Each module keeps the interface it has on LLVM, so that a
   program that runs on LLVM builds unchanged for the VAX. The order is
   the order of the imports:
   1. `Platform`
   2. `Files`
   3. `Modules`, with the VAX backend's module descriptors and commands
   4. `RealDigits` and `Reals` for F and G, and with them `Out.Real` and
      `Err.Real`
   5. `FormattedOutput` and `OutStr`
   6. `In`, `InStr` and `FormattedInput`, over a `LineInput`
   7. `Strings`
   8. `Math` and `MathL`
   9. `Args` and `VT100`
   10. `Texts` and `Oberon`

   Where a module is the same, its fixtures are shared with LLVM: the same
   `.mod` and `expected`, run on the guest. The exceptions are the signal
   handlers in `Platform`, which are step 6's, and anything that differs
   because of VAX reals. Such a difference is written where it is, with a
   fixture of its own.
2. **voc's library modules stay in Phase 20**, which takes them for both
   targets. Step 3 does not port any of them. Phase 20 starts from the
   table above:
   - the 51 "runtime" modules come with step 3;
   - the 17 "VAX reals" modules need F/G versions of `oocLowReal` and
     `oocLowLReal`, and of `ethReals`, `oocRealMath`, `oocLRealMath`,
     `oocBinaryRider` and `ooc2LRealConv` (this one also needs libc), or
     else they are left out on VMS;
   - the "system-specific" and "C" ones are left out on VMS unless Phase
     20 gives them a VMS layer of their own.
3. **Reals are converted by poc's own code, not by the VAX C run-time
   library.** Output already uses `RealDigits`' exact digits. Input
   (`In`, `Strings`, `Reals`, `Texts`) uses an Oberon version of the
   front end's correctly rounded conversion, to F_floating or
   G_floating. The C library is part of VMS, but it brings its own
   start-up and `errno` into a program. Its `atof` was still being fixed
   in 5.5-2 (release notes 3.12.1), and poc could not promise its
   rounding. On LLVM poc uses `strtod`; there the C library is correctly
   rounded and present anyway.
4. **`Files`' typed riders write IEEE 754, as Oakwood's external format
   says**, so that a file of reals written on the VAX reads the same on
   LLVM, and the other way round. Converting G_floating to IEEE double is
   exact except below 2^-1022, where IEEE has only subnormals and the
   last bits round. F_floating to IEEE single is the same below 2^-126.
   Reading an infinity, a NaN, or a value beyond F's or G's range is a
   trap with its own message (proposed status 8, as `ENTIER` out of
   range). A subnormal too small for F or G reads as 0.
5. **`Math` and `MathL` are over `MTH$`**, F and G, through `["VMS"]`
   declarations whose arguments go by reference (step 5's mechanisms; a
   `VAR` parameter is enough until then). An error that `MTH$` signals
   sets voc's `Math.err` and calls `ErrorHandler`, as on LLVM, through a
   condition handler that the module establishes around each call. This
   needs a way to establish a handler from Oberon, which step 5 or step 6
   provides; until then an error ends the program with `MTH$`'s message.
6. **`Out.Flush` writes a part line to a terminal without ending the
   record**, so that `VT100`'s cursor movements reach the screen before a
   line ends. This uses `$QIO` with `IO$_WRITEVBLK`, or RMS with no
   carriage control. To a file, `Flush` keeps doing nothing, so that
   records stay whole.
