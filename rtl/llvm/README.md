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
- `Platform.Mod` - the OS services poc's driver uses, with voc's `Platform`
  signatures: `Chdir`/`CWD`, `GetEnv`, `PID`, `System`, `Unlink`. Each
  is one libc call (`chdir`, `getcwd`, `getenv`, `getpid`, `system`,
  `unlink`, the same on Linux and the three BSDs); an error is -1, not
  voc's errno.
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
  interfaces. `Out` writes through `Console` (unbuffered), and prints
  `REAL`/`LONGREAL` with voc's algorithm; `In` reads standard input with
  `getchar` and real numbers with libc's `strtod`/`strtof`.
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
so poc compiles them itself; a program picks them up through the import
path - the `llvm-gc-*` fixtures set `POC_IMPORT_PATH=../../../rtl/llvm`.
Sources use the `.Mod` spelling; `ReadModuleSource` finds either.
Nothing here is compiled by voc.
