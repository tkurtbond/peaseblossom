# rtl/llvm

Runtime linked into LLVM-targeted programs: bespoke mark-sweep GC
(`GarbageCollectedHeap.Mod`, `ModuleTable.Mod`), a minimal `Console.Mod`
for the first "hello world" milestone, and later fuller Oberon-2-style
`Out.Mod`/`In.Mod`. Must run on Linux, NetBSD, OpenBSD, and FreeBSD (see
`AGENTS.md`).

- `ModuleTable.Mod` - the registry of per-module GC root tables. The
  backend emits a table (`@.roots.<Module>`) for every module with
  pointer-typed module variables, and registers it at the top of the
  module's `_init`, only in a program that contains this module.
- `GarbageCollectedHeap.Mod` - the collector: calloc'd chunks of 16-byte
  granules, bump allocation plus a first-fit free list, mark-sweep with
  precise heap/global tracing (type descriptors, root tables) and a
  conservative machine-stack scan. `Allocate(size, tag)` is the interface
  step 5's `NEW` will call; nothing else is needed to use it. The module's
  own header comment has the layout and the policy.

Written in ordinary Oberon-2 over `SYSTEM.ADDRESS` (no pointer variables),
so poc compiles them itself; a program picks them up through the import
path - the `llvm-gc-*` fixtures set `POC_IMPORT_PATH=../../../rtl/llvm`.
Sources use the `.Mod` spelling; `ReadModuleSource` finds either.
Nothing here is compiled by voc.
