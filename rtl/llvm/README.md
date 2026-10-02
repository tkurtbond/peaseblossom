# rtl/llvm

Runtime linked into LLVM-targeted programs: bespoke mark-sweep GC
(`GarbageCollectedHeap.Mod`, `ModuleTable.Mod`) and the library modules
listed below. Must run on Linux, NetBSD, OpenBSD, and FreeBSD (see
`AGENTS.md`).

- `ModuleTable.Mod` - the registry of per-module GC root tables. The
  backend emits a table (`@.roots.<Module>`) for every module with
  pointer-typed module variables, and registers it at the top of the
  module's `_init`, only in a program that contains this module.
- `Console.Mod` - text output to standard output with voc's `Console`
  interface (`Flush`, `Char`, `String`, `Int`, `Ln`, `Bool`, `Hex`), unbuffered,
  over one `write(2)`. Imported like any module; needs only this directory
  on the import path.
- `Platform.Mod` - voc's `Platform` interface in full (Phase 12 step 5a):
  files by handle, file identities and times, the error tests, the
  clock, the environment, the working directory, signal handlers,
  `OSAllocate`/`OSFree`, `System`, `Exit`. An error code is the errno
  value, as in voc. What is the same on the four systems is called from
  here; the rest is in `Platform.c`, below.
- `Platform.c` - `Platform`'s part in C: open's flags, errno and its values,
  `struct stat`, the clock and signals differ between Linux and the
  BSDs (and NetBSD renames the functions), which only the system's own
  headers know. poc compiles a module's sibling `.c` whenever it compiles
  the module (`LLVMToolchainDriver.CompanionSource`), so it goes into
  `poc-rtl` and into any program that builds `Platform` from source.
- `VT100.Mod` - terminal control with ANSI escape sequences, voc's `VT100`
  interface (Phase 12 step 5b), written for poc: cursor movement, erasing,
  scrolling, colours and attributes, written through `Out`. Unlike voc's,
  every number is written whole and `DSR` sends its argument.
- `Files.Mod` - Oberon files (`File`, `Rider`, `New`, `Old`, `Register`,
  `Close`, `Length`, `Set`, `Read`, `Write`, `ReadString`, `ReadLine`,
  `WriteString`, ...) over C stdio, which is what keeps it portable across
  Linux and the BSDs. A new file is a temporary one until `Register`.
  Needs `NEW`, so the collector modules below are added to any program
  that imports it.
- `Modules.Mod` - the command line: `ArgCount`, `GetArg`, `GetIntArg`,
  `ArgPos`. A program that contains this module gets a `main` taking argc
  and argv, which it passes to `Modules.Init` before any module body runs;
  other programs keep an argument-less `main`.
- `Out.Mod`, `In.Mod` - the Oakwood formatted output and input, with voc's
  interfaces. `Out` writes through `FormattedOutput` (unbuffered), and prints
  `REAL`/`LONGREAL` correctly rounded (`RealDigits.Mod`, big-integer
  arithmetic, no floating point); `In` reads standard input with
  `getchar` and real numbers with libc's `strtod`/`strtof`.
- `Err.Mod` - `Out`'s interface (`Open`, `Flush`, `Char`, `String`,
  `Int`, `Hex`, `Ln`, `Real`, `LongReal`, `Ten`, `IsConsole`) writing to
  standard error, unbuffered (Phase 11 A26). voc has no such module.
- `FormattedOutput.Mod` - the formatting `Out` and `Err` share, each
  procedure taking the descriptor to write to. Internal, like `RealDigits`.
- `FileDescriptorOutput.Mod` - the two OS calls under `FormattedOutput`,
  `Out` and `Err`: `Write` (`write(2)`) and `IsTerminal` (`isatty`). Phase
  11 D11 split them out so that voc compiles the rest (below).
- `RealDigits.Mod` - the exact decimal digits of a `LONGREAL`, rounded to
  any number of significant digits (nearest, ties to even): what `Out.Real`/
  `Out.LongReal` print from. Internal, not part of Oakwood. The same
  algorithm as `src/front/DecimalToDouble.Digits`, kept apart because poc's
  own source is strict Oberon-2 and this one uses `HUGEINT` and `SYSTEM`.
- `Strings.Mod`, `Math.Mod`, `MathL.Mod` - the remaining Oakwood basic
  modules, with voc's interfaces. `Strings` is plain Oberon-2 (plus
  `strtod`/`strtof` for `StrToReal`/`StrToLongReal`); `Math` and `MathL` are
  written over libm's double functions (the build links `-lm`), with voc's
  error codes and handler (`Math.ErrorHandler`, `Math.err`), and are not
  derived from voc's LGPL ones.
- `GarbageCollectedHeap.Mod` - the collector: calloc'd chunks of 16-byte
  granules, bump allocation plus a first-fit free list, mark-sweep with
  precise heap/global tracing (type descriptors, root tables) and a
  conservative machine-stack scan. `Allocate(size, tag)` is the interface
  `NEW` calls (Phase 9 step 5); `poc` adds both this and `ModuleTable` to
  any program that calls `NEW`, so a source module never imports them for
  that - it only needs this directory on the import path. The module's
  own header comment has the layout and the policy.

Written in ordinary Oberon-2 over `SYSTEM.ADDRESS` (no pointer variables),
except `Platform.c`, so poc compiles them itself; a program picks them up through the import
path - the `llvm-gc-*` fixtures set `POC_IMPORT_PATH=../../../rtl/llvm`.
Sources use the `.Mod` spelling; `ReadModuleSource` finds either.
voc compiles four of these for Stage 0 (Phase 11 D11), so that the
voc-built poc writes its errors to standard error through the same `Err`:
`RealDigits`, `FormattedOutput` and `Err` from here, over
`rtl/voc/FileDescriptorOutput.Mod`, voc's version of the one module that
calls the operating system. They must stay within what voc accepts.
