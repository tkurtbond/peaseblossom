# The LLVM toolchain and how poc drives it

Moved here from `AGENTS.md` on 2026-09-27, which keeps a summary of each
point below.

Used by `poc`'s Phase 8+ LLVM backend (`PLAN.md`) — `LLVMToolchainDriver.Mod`
shells out to these rather than linking against LLVM's own C++ API.

- Installed via system packages (Fedora), both on `PATH`: `/usr/bin/clang`,
  `/usr/bin/llc`.
- Version confirmed 2026-09-18: `clang version 22.1.8 (Fedora
  22.1.8-4.fc44)`, matching `llc`'s `LLVM version 22.1.8`. Host target
  triple: `x86_64-redhat-linux-gnu`; host default data layout:
  `e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128`
  (from `clang -S -emit-llvm` on an empty `int main(){return 0;}`).
- **Build invocation: one `.ll` and one object per module** (Phase 12 step
  2a, 2026-09-27; until then a single `clang <program>.ll -o <exe>`, Phase 8
  step 1). `-emit-llvm-ir` writes `<Module>.ll` for every module of the
  program, `-build` also runs `clang -c` on each to `<Module>.o` and links
  the objects with one more `clang`. Each module's `_init` runs its body
  once, after calling its imports' `_init` in IMPORT-list order (voc's
  order is alphabetical); `main`, in the main module's `.ll`, calls the
  runtime's and then the main module's. Each module's object defines
  `<Module>.-key.<hash of its .sym>` and refers to its imports' keys, so an
  importer links only with the interface it was compiled against (step 2b;
  `-build` and `-emit-llvm-ir` write the main module's `.sym` too).
  **Libraries** (step 2c): `poc -library <name> <file>...` builds the
  modules of those files (their imports must be among them or in a library)
  into `<output-dir>/<triple>/<O2|OC>/`: `.sym`/`.ll`/`.o` per module,
  `lib<name>.a`, `lib<name>.so` (`.so.0.0` on OpenBSD), the manifest
  `<name>.library` and `<Module>.owner` files. The library path is
  `-library-path` (repeatable), then `POC_LIBRARY_PATH`, then
  `<poc's dir>/../lib/poc`; `-clear-library-path` drops all three. A
  module a library on the path has is taken from it, never from source;
  `-build` links the libraries' archives, `-shared-libraries` their shared
  libraries. poc refuses a module two libraries have and a library
  compiled against another's old keys (`src/driver/Libraries.Mod`), warns
  when a library's module hides another library's or differs from source
  beside the program, and follows an import found nowhere with notes on
  where it looked (step 2e). A module with no source can be given as its
  `.sym` and `.o`, to `-build` (found on the import path) and to `-library`
  (named by either file): poc checks the pair against the object's own
  symbols, read with `nm -P`, where each module defines
  `<M>.-key.<O2|OC>.<hash>` and `<M>.-target.<triple>` and refers to its
  imports' keys (step 2f; every object is compiled `-fPIC`). `poc -compile
  <file>...` (voc's `-c`) makes a module's `.sym` and `.o` without a
  program. `poc -install-library <name>` copies a library into `-output-dir`
  or poc's own `../lib/poc`; a program's run-time search path has each
  shared library's directory relative to it (`$ORIGIN`) and absolute.
  `make` builds `rtl/llvm` as the library `poc-rtl` into
  `build/lib/poc/<host triple>/{O2,OC}` (step 2d), so a program links the
  runtime already compiled; the bootstrap stages use `-clear-library-path`
  and compile it from source. A
  `.ll` file emitted by `LLVMCodeGenerator.Mod` must set its own `target
  datalayout`/`target triple` explicitly (matching the values above for the
  host, or the `-target` flag's chosen triple) — omitting them makes clang
  silently substitute the host triple with a `-Woverride-module` warning,
  which would mask a real target mismatch on cross-compiles. The driver
  also passes `-lm` (Phase 10 step 6): `rtl/llvm`'s `Math`/`MathL` call libm,
  a library apart from libc on Linux and all three BSDs, and `clang` does not
  link it by itself (an undefined `sin` at link time).
  **Stack alignment on 32-bit x86 BSDs** (2026-09-21): the i386 System V ABI
  keeps the stack 16-byte aligned at a call, and the C library there is built
  on it (NetBSD's libm does aligned SSE moves through the frame pointer), but
  LLVM assumes it only for i386 Linux - for NetBSD, OpenBSD and FreeBSD i386 it
  assumes 4 - and a process starts `main` with the stack at 4 modulo 16. So
  for a 32-bit x86 triple whose OS is one of those BSDs (`LLVMTypes.
  NeedsStackRealignment`) poc emits the module flag
  `override-stack-alignment` = 16 (LLVM keeps every call it emits aligned) and
  `"stackrealign"` on `@main` (the one frame that starts misaligned); either
  alone still crashed `sin` on NetBSD. Linux and all 64-bit and ARM targets get
  neither, so their IR is unchanged (`llvm-stack-realign`).
- **A module's part in C** (Phase 12 step 5a, decided with the user
  2026-10-02): a C file beside a module's source with the same base name
  (`rtl/llvm/Platform.c` beside `Platform.Mod`) is compiled by `clang -c`
  for the target, `-fPIC` and the same `-O` level (and `-flto` under
  `-lto`), whenever poc compiles the module from source, to `<Module>.c.o`
  beside the module's object. That object goes wherever the module's
  goes: into the link, into a library's archive and shared library, and
  into `-compile`'s output; a module given as its `.sym` and `.o` (or
  `.ll`) brings the `<Module>.c.o` beside that file, if there is one
  (`LLVMToolchainDriver.CompanionSource`/`CompanionObject`). It is for what
  an Oberon declaration cannot follow because poc does not know which of
  the four systems it compiles for: flag and errno values, structure
  layouts, NetBSD's renamed functions. Such a file's own names should
  contain `-` (through `__asm__` labels, as `Platform.c`'s do:
  `Platform.-open`), so that they never match a module's. Fixture
  `llvm-c-part`.
- **Optimization level** (Phase 11 D13, 2026-09-26): `poc -opt <level>`
  makes `-build` pass clang `-O<level>`, one of `0`, `1`, `2`, `3`, `s`, `z`,
  `g` (not `-O<level>` itself: poc's `-O2`/`-OC` are voc's size-model flags).
  The default is `-O2`, but `-O0` for 32-bit x86, whose reals are x87
  arithmetic (`doc/language-extensions.md`, "Overflow, division and reals";
  poc must run on a Pentium II, so no SSE2). `SYSTEM.GET`/`PUT`/`MOVE` are
  volatile, so an optimized build keeps them. `make check-opt2` builds
  everything at `-O2`, Stage 1/2 included (in `build/opt2`).
- **Link options** (Phase 12 step 1, 2026-09-27): `poc -static` makes
  `-build` pass clang `-static` (a fully static executable; on Linux it needs
  `glibc-static`, on OpenBSD it is a static PIE); `poc -link <arg>`, repeatable,
  passes `<arg>` to clang as one word, after the objects and before `-lm`
  (`-link -lz`, `-link -L<dir>`); `poc -verbose` prints the clang command on
  stderr. Fixture `poc-link-flags`.
- **Whole-program optimization** (Phase 12 step 2g, 2026-09-27): `poc
  -lto` compiles each module to LLVM bitcode (`clang -c -flto`) and links
  with `-flto` (on NetBSD also `-fuse-ld=lld`: its GNU ld cannot), so
  LLVM inlines and removes code across modules. A module given as its
  `.sym` and `.ll` takes part (its key, target and imports read from the
  text, `Libraries.ReadIR`); a library built with `-lto` says `lto` in its
  manifest and makes any link of its archive use `-flto`. A bitcode `.o`
  beside a `.sym` is refused without its `.ll`: `nm` cannot read bitcode
  on OpenBSD or NetBSD. For 32-bit x86 NetBSD `-lto` is ignored with a
  warning (neither GNU ld nor lld links bitcode into an executable that
  runs there). `make check-lto` runs the suite with `-lto` (not
  part of `make check`). Fixture `llvm-lto`.
- **Debug information** (Phase 11 A16, stage (a), 2026-09-26): `poc -g`
  emits DWARF metadata for gdb and lldb - the procedures' names
  (`List.Insert`, `List.Insert.Find` for a nested one,
  `List.NodeDesc.Print` for a type-bound one, `List_init` for a module
  body) and the source lines, so a breakpoint by name or `file:line` and a
  backtrace work. It leaves the optimization level alone; debug at
  `-opt 0` or `-opt g`. The language claimed is C (`DW_LANG_C99`): DWARF
  has no code for Oberon, and lldb supports neither Modula-2 nor Pascal
  (gdb users can `set language modula-2`). Every instruction of a
  procedure or module body carries its statement's position, attached by
  `LLVMCodeGenerator.WriteLn`; a procedure's prologue carries none, so a
  breakpoint stops at the first statement. Stage (b), the same day:
  parameters (value and plain `VAR`) and local variables of the basic
  types, so `info args`, `info locals`, `print` and lldb's `frame
  variable` show them (`LLVMCodeGenerator.DeclareDebugVariable`, a call of
  `llvm.dbg.declare` on each one's slot). Each basic type is a typedef of a
  DWARF base type under its Oberon name, so lldb shows `(INTEGER) n = 3`,
  not `(short)`. A one-byte integer (`SHORTINT`, `SYSTEM.INT8`) shows as
  a character too (`5 '\005'`), since C's only one-byte integer is
  `char`; a `SET` as its number. Stage (c), the same day: records (field
  by field, the base type's first, as a structure named `Module.T`, or
  `Module.P^` for the record a `P = POINTER TO RECORD ...` points to),
  fixed arrays, pointers (to what they point to, so `p->next->x` works),
  procedure variables, `SYSTEM.PTR`, `VAR`
  record parameters and receivers, and module variables. Each module is a
  compile unit of its own, so a name finds the current module's variable
  first. Fixture `llvm-debug-info` (gdb 7 or later - on OpenBSD the
  `gdb` package's `egdb`, as the base gdb 6.3 cannot read it - else lldb;
  skipped with neither). Stage (d), the same day: an open-array
  parameter is an array whose lengths are artificial variables `LEN(a)`,
  `LEN(a, 1)`, ... (as clang describes a C variable-length array); a
  pointer to an open array points to its heap block, `{len, data}`, with
  `data`'s counts DWARF expressions that read `len`; a nested procedure
  shows the enclosing procedure's variables it uses. A by-reference
  argument is described through a stack slot (`DW_OP_deref`), since its
  register is reused. gdb shows all of it; lldb 22 does not evaluate
  those counts: element access (`p->data[2]`, `a[1]`) and the lengths are
  right, but it prints a multi-dimensional open array, and a heap open
  array as a whole, wrongly or empty - as it does C's multi-dimensional
  variable-length arrays. A `VAR` record shows its static type; its
  hidden type tag is not used.
- `llc` is **not** part of the normal build path — reserved as an optional
  `-dump-asm`-style debug aid for reading generated assembly in golden-file
  tests. Usage: `llc <file>.ll -o <file>.s` (its default output filetype is
  already textual assembly; unlike `clang`, it has no `-S` flag — passing
  one is a hard CLI error, `Unknown command line argument '-S'`).
