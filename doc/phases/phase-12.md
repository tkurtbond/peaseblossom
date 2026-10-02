# Phase 12 — Detailed library/module support (voc's options, static/dynamic libraries, voc's module inventory)

Moved here from `PLAN.md` unchanged on 2026-10-02, once the phase was done
(step 6's record written at the close-out, and the deferred CPU question
moved to `PLAN.md`'s "Open design questions"). `PLAN.md` keeps the heading,
the goal, and a list of the steps, so a reference elsewhere to "`PLAN.md`
Phase 12 step N" means step N here.

**Goal**: decide, from primary sources and not from memory, what poc must
offer *beyond* what Phases 9-10 already give it - the command-line
surface a voc user expects, a way to build the libraries a program links
against, and which of the libraries and modules voc supplies are worth
having - and then build what the decisions call for. Phase 10 covers
exactly what poc's own source needs plus the Oakwood basic modules and
`SYSTEM`; this phase is everything else, and it starts as investigation:
steps 1-3 produce written inventories and decisions (recorded here and in
`AGENTS.md`), and only steps 4-6 write code. Placed before the VAX/VMS
backend (Phase 14) because the library question is an LLVM/Unix one and
nothing in the VAX work depends on it.

**Explicit non-goals**: the VAX/VMS backend, which needs its own answer to
"what is a library" (VMS shareable images, object libraries) and is not
decided here; and the self-hosting bootstrap itself, which is Phase 10's
own exit gate - this phase may assume it has been reached, or not, as
convenient, but must not be a prerequisite of it.

1. **Which of voc's command-line options poc needs.** Go through every
   option `voc` accepts and decide, for each, whether poc implements it,
   implements it differently, or does not. The sources are the option
   list `voc` itself prints with no arguments, `doc/Compiling.md` and
   `doc/Features.md` in the clone under `/usr/local/sw/src/lang/Oberon/
   vishap/compiler`, and - since the printed list may be incomplete -
   `OPM.Mod`'s own option parsing (the source of truth: probe anything it
   accepts that the usage text does not mention). As of voc 2.1.0 the
   printed groups are: run-time safety (`-p` NIL-initialize pointers, `-a`
   halt on assertion failure, `-r` range checks, `-t` type-guard halt,
   `-x` index-range halt); symbol-file management (`-e`, `-s`, `-F`);
   C-compiler and linker control (`-m`/`-M` main module linked
   dynamically/statically, `-S` do not call the C compiler, `-c` do not
   link); miscellaneous (`-f` no VT100 control characters, `-V`
   debugging messages); the size model (`-O2`, `-OC`, and `-OV`, which poc
   does not have); and target address size and alignment (`-A44`,
   `-A48`, `-A88`). poc already has `-O2`/`-OC`, `-target <triple>`,
   `-build`, `-o`, `-emit-llvm-ir`, `-emit-interface`, `-import-path`,
   `-output-dir`. Questions the triage must answer with evidence rather
   than assume: which safety checks poc emits unconditionally today (NIL,
   index, type guard, `WITH`, `CASE`, array length) and which of them
   voc's switches would let a user turn off or on (`-r` range checking
   has no poc counterpart at all). **`-A44`/`-A48`/`-A88` answered
   (2026-09-20, `000-todo.org`): not applicable, and poc needs no
   counterpart.** voc's `-A` exists because it generates portable C and
   has no other way to tell the *downstream* C compiler's ABI (address
   size and struct alignment are genuinely independent there - `-A48`,
   32-bit addresses with 64-bit alignment, is a real 32-bit-Windows/ARM
   quirk); poc emits an explicit LLVM `target datalayout` string per
   `-target` triple (`LLVMCodeGenerator.dataLayoutW64`/`dataLayoutW32`,
   verified against real hardware, Phase 8 step 13) that already pins
   down both axes together - choosing the triple chooses both at once,
   with nothing downstream left to infer them independently. What
   `-e`/`-s`/`-F` mean for a `.sym` poc always regenerates whole-program
   (Phase 9 step 4a); how `-m`/`-M`/`-S`/`-c` map onto `-build`,
   `-emit-llvm-ir` and step 2's library modes; and whether `-OV` is worth a
   third size model. The result is a table - option, voc meaning, poc
   decision (adopt as-is / adopt with a different meaning / not
   applicable / deferred), reason - kept in `PLAN.md` (or a file it names),
   plus the flags it adopts, each implemented in `Poc.Mod` with a fixture
   and cross-checked against real voc where voc's behavior is
   observable. **Testing**: a golden `-help`/usage fixture, and a fixture
   per adopted flag that would otherwise be untested.
   **Done (2026-09-27, decided with the user): `doc/voc-options.md`** has the
   table, every option probed against voc. Adopted: `-r` as `-range-checks`
   (`SHORT` of an integer and `CHR` that do not fit trap, status 14, off by
   default), `-M` as `-static`, `-V` as `-verbose` (the clang command), and
   voc's `LDFLAGS`/`LDLIBS` as a repeatable `-link <arg>`. No switch turns a
   check off (`-a`, `-t`, `-x`, `-p`: A14 and D16 stand). `-S`/`-m` are
   `-emit-llvm-ir`/`-build`; `-c` goes to step 2; `-e`/`-s`/`-F`, `-f`,
   `-OV` and `-A..` do not apply. The triage found two checks the report
   requires that voc makes and poc did not, now always on: a function that
   reaches its `END` (status 12) and a record assigned to a `VAR` parameter
   or `p^` whose dynamic type extends its static type (status 13); and, on the
   way, a bare `RETURN` in a function (now a compile-time error), a record
   assignment to a `WITH`-narrowed `VAR` parameter that copied only the base
   record's fields (fixed), and flags with no command after them, which
   exited 0 having done nothing (now the usage text, status 1). Fixtures
   `llvm-range-checks`, `llvm-return-trap`, `llvm-record-assign-trap`,
   `semantic-reject-bare-return`, `poc-link-flags`, `poc-usage`.

2. **Building static and dynamic libraries with poc.** Decide how a
   program compiled by poc links against libraries poc itself built, and
   build it. voc's answer is the reference (`libvoc-O2.a`/`.so` and
   `libvoc-OC.a`/`.so` in its install `lib` directory - one library per
   size model, since its `.sym` files carry computed sizes and offsets);
   poc's differs at the root, since a `.sym` is target-independent source
   (Phase 7, Phase 9 step 4a) but the object code is not - it is specific
   to word size, size model and target triple, so a library's identity
   is that whole tuple and the layout of its output directory has to say
   so. Questions to settle: what the unit of a library is (a set of
   modules with their `.sym` files, found through `-import-path`); the
   command-line shape (a "compile these modules into a library" mode and
   the "link against it" flags, informed by step 1's triage of `-m`/`-M`/
   `-c`); a static library as an `ar` archive of per-module objects
   (`clang -c`, then `ar`) and a dynamic one as `clang -shared` over
   position-independent objects - on Linux, NetBSD, OpenBSD and FreeBSD,
   which differ in the details (runtime search path, `-rpath`, symbol
   versioning) more than they will look like they do; exported-symbol
   visibility, given that every Oberon procedure is `@Module.Proc`; what
   module initialization and `ModuleTable`'s root registry do when the
   modules are in a library, including in a shared one loaded by more than
   one program (Phase 9 step 4's per-module GC root tables); where the
   collector and the rest of `rtl/llvm` live (in every library that needs
   it? in one library of their own? - two copies of the collector in one
   process would each be blind to the other's heap); how the `main`
   generated for a program finds the initializers of every module it
   links, library or not; and record-layout and `ProcTab` stability
   across a library rebuild, since Phase 9 step 4a's importer reproduces a
   base type's layout from the `.sym`. The deliverable is the design,
   written into `PLAN.md`, then the implementation: `poc` builds `rtl/llvm`
   itself as a library and a program links against it both ways.
   **Testing**: build a small library of two or three modules with
   dependencies between them; link a program against it statically and
   dynamically; run both, at both word sizes, on Linux and on the BSD
   hosts (the same real-hardware access as Phase 9 step 9); and the
   negative cases - a `.sym` that does not match the library it names, a
   missing library - fail with a message and not a crash.

   **Design (decided with the user 2026-09-27).** Four decisions, then
   what follows from them.

   - *Every module is compiled on its own* (as voc does), library or not:
     one `.ll` and one object per module, which declares what it uses of
     its imports. `-build` compiles each module of the program found as
     source and links the objects; cross-module inlining is given up.
   - *Initialization is voc's*: each module's `_init` has a flag of its
     own, returns at once when it is set, and otherwise sets it, calls the
     `_init` of each of its imports in declaration order, and runs the
     module's body. `main` sets the stack base and calls the main module's
     `_init` only, so a program needs no list of the modules a library
     keeps to itself, and the order does not depend on the link.
   - *A library is a named set of modules, and rtl/llvm is one*:
     `poc -library <name> [-output-dir <dir>] <file>...` compiles the files
     named (and nothing else: every import must be one of them or come from
     a library already on the library path) and writes, into
     `<dir>/<triple>/<O2|OC>/` (a library is specific to its target and size
     model, and so are its `.sym` files, which carry folded constants: B1),
     `lib<name>.a`, `lib<name>.so`, each module's `.sym` and a manifest,
     `<name>.library` (its modules with their keys and imports, the
     libraries it needs, the triple and size model). A module belongs to
     exactly one library: poc refuses to build a module into a library when
     one on the library path has it already, and to link two libraries that
     both have it, so a process never holds two collectors. rtl/llvm is the
     library `poc-rtl`, built by `make` for the host, both size models. A
     program links its libraries statically; `-shared-libraries` links them
     dynamically, with a run-time search path (`-rpath`) naming each one's
     directory.
   - *Module keys, checked twice*: each module's object defines the symbol
     `<Module>.-key.<hash>`, the hash that of its `.sym` text, and every
     importer's object references it, so a link against a module whose
     interface changed after the importer was compiled fails in the linker
     whoever runs it. poc also compares, before it links, the keys each
     library's manifest records for its own imports with the keys of the
     libraries it will link, and names the stale library in a message of
     its own.

   Following from those (poc's own choices, open to change):

   - The library path is `-library-path <dir>` (repeatable, like
     `-import-path`), seeded from `POC_LIBRARY_PATH` and, last, the `lib/poc`
     directory beside the directory poc's executable is in. A module an
     import names is taken from a library when a manifest on the path has
     it, otherwise from source on the import path. When no `poc-rtl` exists
     for the target and size model (a cross build, a fixture that sets no
     library path), rtl/llvm is found as source like any module and
     compiled into the program, as today.
   - `-emit-llvm-ir <file>` writes the `.ll` of every module of the program
     compiled from source (the one named has `main`), where `-build` would;
     `-build` writes each module's `.ll` and object there too, so a build's
     output directory fills with them as it fills with `.sym` files today.
   - Objects for a library are position-independent, and the same objects
     go into both the archive and the shared library. Symbols keep their
     default visibility: an extension's method table can name an imported
     record's hidden type-bound procedure, so nothing a module defines can
     be assumed private to it. What a module makes for itself alone - an
     anonymous record's type descriptor and initialization procedure,
     strings, trap messages - is `internal`/`private`, so two objects never
     both define it.
   - voc's `-c` (compile, do not link) gets no flag of its own for now:
     `-library` already compiles without linking a program, and
     `-emit-llvm-ir` writes every module's `.ll`.

   **Sub-steps**, each its own commit, each passing `make check`:
   **2a** per-module code generation and voc's initialization (no libraries
   yet: `-build` compiles the program's modules one by one and links them);
   *done 2026-09-27*: `LLVMCodeGenerator.GenerateModule` writes one module's
   IR, declaring everything each module of its import closure defines (and
   the runtime modules' the generated code calls without an IMPORT; an
   unused declaration costs nothing), and a guarded `_init` that calls its
   imports' in IMPORT-list order (voc's is alphabetical, from its sorted
   scope). `main` also calls `ModuleTable_init` and
   `GarbageCollectedHeap_init` before the main module's, since no IMPORT
   names them. Not yet `internal`: an anonymous record's descriptor and
   initialization procedure keep their module-prefixed global names, since
   in one run another module may still name another's (2c changes that);
   fixture `llvm-module-init-order`;
   **2b** module keys; *done 2026-09-27*: `ModuleInterface.KeyOf` gives
   the 64-bit FNV-1a hash of a module's `.sym` bytes (computed a byte at a
   time, so poc needs no 64-bit integer for it), recorded whenever a run
   writes or reads a `.sym`; whole-program commands now write the main
   module's `.sym` too, so every module has one. Each module's `.ll`
   defines `@<M>.-key.<hash>` and lists its imports' keys in
   `@<M>.-imports`, kept by `@llvm.used`; fixture `llvm-module-keys`
   (a new body relinks, a new interface fails in the linker naming the
   key); **2c** `-library`, the manifest, the library path,
   static and dynamic linking, and the refusal of a second copy of a module;
   *done 2026-09-27*: `src/driver/Libraries.Mod` (the library path, manifests,
   `<Module>.owner` files naming a module's library - no directory listing
   needed -, link order, and the refusals: a module two linked libraries
   both have, a library compiled against a key another library no longer
   has, a needed library missing); `poc -library`, `-library-path`,
   `-clear-library-path` (which also leaves out `POC_LIBRARY_PATH` and
   poc's own `../lib/poc`, found through the shell's `command -v`),
   `-print-library-path`, `-shared-libraries`. A module a library has
   enters the program from its `.sym` (`ModuleList.inLibrary`, declared
   and not generated; `ModuleInterface.libraryLookup` makes the checker
   read the library's `.sym`). Libraries' objects are `-fPIC`; the shared
   library is `lib<name>.so` (`.so.0.0` on OpenBSD) and is linked against
   the libraries it needs; `-shared-libraries` gives the program an
   absolute run-time search path. The descriptor and initialization
   procedure of a record with no name are now `internal`. Fixture
   `llvm-libraries`;
   **2d** `poc-rtl`, built by `make`, used by default when present;
   *done 2026-09-27*: `make` builds `rtl/llvm` as the library `poc-rtl`
   into `build/lib/poc/<host triple>/{O2,OC}` (and Stage 1's into
   `build/stage1/lib/poc`, `check-opt2`'s into `build/opt2/lib/poc`), where
   each poc's default library path finds it, so a program links
   `libpoc-rtl.a` instead of compiling the runtime again. A library
   module's `.sym` cannot say whether its bodies call `NEW`, so a program
   with a module from a library gets the collector whenever a library on
   the path has `GarbageCollectedHeap`. The bootstrap stages build with
   `-clear-library-path` (poc from source, independent of any library;
   the fixed point compares every module), and so do the fixtures that
   show or relink the objects compiled from source (`llvm-module-keys`,
   `poc-link-flags`); **2e** using modules and libraries (added with the
   user 2026-09-27, after trying four ways a program gets its modules with
   the 2d poc): (1) the program's own modules and poc's runtime, which
   works with no flags, the runtime linked from `poc-rtl`; (2) modules
   someone else shared, which work as source through `-import-path`
   (compiled with the program, their `.sym`/`.ll`/`.o` written beside it)
   but not as `.sym` and `.o` files alone ("cannot find source"); (3) the
   user's own library, which works (`-library`, then `-library-path`,
   statically or with `-shared-libraries`); (4) several libraries from
   others, which works too: a library's needs are linked after it, and a
   library compiled against another's old key is refused with a message
   that names both. What falls short, and this sub-step does:
   - Diagnostics. A module found nowhere gives only "unknown imported
     module", in the program or, for a library's missing need, in the
     library's `.sym` (`Loud.sym:2:10`). The message is to say what was
     searched - the import path and the library path, and the triple and
     size model the library was looked for under, so a library built for
     `-O2` only is recognized as such under `-OC` - and, for a library
     whose needed library is not on the path, name both libraries.
   - Shadowing. A library module is taken in preference to source of the
     same name, and the first library on the path that has a module
     shadows the others (a module in two libraries is refused only when
     both are linked). Both are to be warned about, naming what was
     passed over; the rules themselves stay.
   - Compiled modules outside a library: decided, not supported. A library
     is the only compiled form poc takes (one module is a library too), so
     the key checks stay in one place; the "cannot find source" message is
     to say so and point at `-library`.
   - Installation: `poc -install-library` copies a library's files for one
     triple and size model into `<prefix>/lib/poc/<triple>/<O2|OC>/`, by
     default the `../lib/poc` an installed poc already searches, so every
     build finds it with no flag; and a program linked with
     `-shared-libraries` finds its shared libraries through a run-time
     search path that survives moving the program and its libraries
     together (`$ORIGIN`-relative, to be checked on each of the four
     systems), not only the absolute directory it was built against.
   - Deferred, not in this sub-step: incremental builds (skipping a
     module whose source and imports' keys are unchanged; every `-build`
     now compiles every module that is not in a library).
   Fixtures: each of the four ways, with the messages and warnings above
   as golden output. *Done 2026-09-27*: an import found nowhere is followed
   by notes (`Diagnostics.Note`, through the hook
   `ModuleInterface.explainMissingModule`): the files looked for and
   where, the library path for the triple and size model, a library that
   has the module for the other size model, a library's need that is
   missing; its uses are not each reported again. A `.sym` without source
   names the file and points at `-library`. A manifest records each
   module's source hash (`source <Module> <key>`), so source beside the
   program is warned about only when it differs from the library's; a
   library whose module an earlier one on the path has is warned about
   (`Libraries.WarnHidden`). `poc -install-library <name>` (to
   `-output-dir`, else poc's `../lib/poc`: `Libraries.PocLibraryDir`)
   copies the manifest, archive, shared library, `.sym` and `.owner` files,
   replacing an earlier copy and refusing a module another library there
   has. The run-time search path is each library's directory relative to
   the executable's or shared library's (`$ORIGIN/...`, when they share a
   directory other than the root), then the absolute one; a shared library
   also has `$ORIGIN`, and both are linked with `-z origin`, without which
   OpenBSD's `ld.so` does not expand `$ORIGIN`. `check-opt2` gives each of
   its two suites' poc `poc-rtl` in its own `../lib/poc`, as `make` does
   (the Stage 0 poc copied to `build/opt2/stage0/bin`); 2d's optimized
   Stage 1 had found none, and compiled the runtime from source. Fixture
   `llvm-using-modules`;
   **2f** compiled modules without source (decided with the user
   2026-09-27, reversing 2e's "a library is the only compiled form": some
   people do not want to share source). Both `-build` and `-library` take
   a module given as its `.sym` and `.o`, found together on the import
   path, when there is no source for it (source still wins, so a stale
   `.sym` never outranks it). The object describes itself, read with `nm`
   (on Linux and all three BSDs): its key symbol names the size model too,
   `<Module>.-key.<O2|OC>.<hash>`, so an importer linked with an object of
   the other model fails in the linker as a stale interface does, whoever
   links it; a marker symbol, `<Module>.-target.<triple>`, defined and
   never referred to, names the triple, which poc checks (the linker does
   not tell x86_64 Linux from x86_64 FreeBSD); its undefined `-key.`
   symbols are its imports and the keys it was compiled against; an
   undefined `GarbageCollectedHeap` symbol says it uses the collector. poc
   checks the pair: the `.o` must define the key of the `.sym`'s hash, for
   this triple and model, and each import must be source, a pair or in a
   library, with the key the `.o` names. A pair's `.o` goes on the link
   line; `-library` takes pairs as members, the manifest's keys from the
   `.sym` and `nm`, and no `source` line. Objects are compiled
   position-independent (`-fPIC`) always, not only for a library, so a
   `-build` object can go into a shared library. `poc -compile` makes a
   module's `.sym` and `.o` without a program. Fixtures: a program and a
   library built from pairs; the refusals (a `.o` that does not match its
   `.sym`, another triple, another size model, an import with another
   key). *Done 2026-09-27*: `LLVMCodeGenerator.KeySymbol` names the model,
   `EmitModuleKeys` defines the target marker; `Libraries.ReadObject` runs
   `nm -P`; `Poc.DiscoverCompiledModule` checks a pair and enters it as
   `ModuleList.compiled`, declared and not generated, its `objectPath`
   linked (and the collector added when its object calls it). The pass
   that regenerates `.sym` files from source now also follows a `.sym`'s
   imports, so an import of a pair still gets its `.sym` from its source.
   `poc -compile <file>...` (voc's `-c`, added to 2f with the user the
   same day) compiles the modules named to `.sym`, `.ll` and `.o`, with no
   `main` and nothing linked (`Poc.CompileOnly`, `LLVMToolchainDriver.
   Compile`); their imports are checked, not compiled, and a module named
   is compiled even when a library on the path has it (poc -library's
   files and -compile's are both `members`; only -library requires every
   import to be one or in a library, `membersOnly`). Fixture
   `llvm-using-modules` (sections 2 and 5);
   **2g** whole-program optimization, `poc -lto` (decided with the user
   2026-09-27). Opt-in, the default link unchanged: LTO links are slower,
   and IR and bitcode are tied to the LLVM version that reads them, where
   an object is not. With `-lto`, `-build` compiles each module's `.ll` to
   LLVM bitcode (`clang -flto -c`) and links with `-flto`, so LLVM
   optimizes the modules as one program: inlining across modules, removing
   procedures nothing calls, folding across module boundaries. What takes
   part: the program's own modules; a module given as its `.sym` and `.ll`,
   a third kind of pair beside 2f's `.sym` and `.o`, its key, target and
   imports read from the `.ll` text instead of with `nm` (and refused with
   a clear message when this clang cannot read it); and libraries built
   with `-lto` (`poc-rtl` too, when `make` is asked for it), whose archive
   holds bitcode. A `.sym`/`.o` pair and a library of ordinary objects
   still link, without optimization across their boundary. `-compile
   -lto` writes a module's bitcode `.o`. Toolchain, probed 2026-09-27 with
   a two-file `.ll` LTO build: the default linker works on atla (GNU ld
   2.46 with LLVM's plugin; no `ld.lld`), cymoril (lld 19) and alerik (lld
   19); on artos GNU ld 2.42 fails and pkgsrc's `ld.lld` works, so on
   NetBSD poc passes `-fuse-ld=lld`; rackhir not yet probed. Little to gain
   on 32-bit x86, whose default is `-O0` (x87 reals). The key and target
   symbols are constants kept alive, so the checks of 2b and 2f still hold
   under LTO. A `.ll` is readable IR, much easier to reverse than an
   object: `.sym`/`.ll` is for optimization, not for sharing a module
   without its source. Fixtures: a program built with `-lto` from source,
   from a `.sym`/`.ll` pair and with an LTO `poc-rtl`, with the same output
   as without; a cross-module call inlined (the optimized IR or the
   executable's symbols); a `.ll` for another target or size model
   refused. *Done 2026-09-27*: `LLVMToolchainDriver.lto` adds `-flto` to
   each `clang -c` and to the link (and `-fuse-ld=lld` on NetBSD,
   `AppendLTOOptions`); `ltoLink` does the same for a link with an LTO
   library's archive in it, since a link without `-flto` fails on bitcode
   with GNU ld (atla, artos), so a library built with `-lto` (manifest line
   `lto`, `Library.lto`) can be linked by a program built without it; its
   shared library is ordinary code. What is beside a `.sym` with no source
   (`Poc.CompiledFiles`): the `.ll` when there is one and `-lto`, no `.o`,
   or a `.o` that is bitcode; else the `.o`. A bitcode `.o` alone is
   refused (nm cannot read bitcode on OpenBSD or NetBSD): give its `.ll`.
   `Libraries.ReadIR` reads the key, target and imports from the `.ll`
   text; the module enters the program with `ModuleList.irPath` and is
   compiled to `<Module>.ir.o` in the output directory, so that a `.o`
   beside the pair is never overwritten; `-library` given a `.sym`, `.o` or
   `.ll` takes the same one, copying the `.ll` into the library to compile
   to `<Module>.o` there. A `.ll` clang cannot compile gets a note that it
   may be from another LLVM version. For 32-bit x86 NetBSD `-lto` is
   dropped with a warning: GNU ld cannot link bitcode, and lld's i386
   executables fail to run there even for plain C (probed on artos, NetBSD
   11 amd64). `make check-lto` (not part of `check`)
   runs the suite with a wrapper that adds `-lto`, against a `poc-rtl`
   built with it, as `check-opt2` does. Fixture `llvm-lto`;
   **2h** the fixtures this step's testing paragraph asks for, on Linux and
   the BSD hosts, at both word sizes, and the rackhir run of step 2's
   commits. *Done 2026-09-27*: fixture `llvm-libraries-i686` builds
   `llvm-libraries`' two dependent modules into a library for 32-bit x86
   (`i686_triple`: i686 Linux on atla, `-m32` on the BSDs, the host's own
   on cymoril), on a `poc-rtl` built for it, under `-O2` and `-OC`, and
   links and runs a program with it statically and dynamically (the
   shared one only where a 32-bit program can use a shared library,
   `i686_can_run_shared`: NetBSD amd64's 32-bit compatibility has static C
   libraries only, so there it fails with "Exec format error" even for
   plain C); the
   64-bit side is `llvm-libraries`, `llvm-using-modules` and `llvm-lto`.
   Its failures are messages: a library whose needed `poc-rtl` is not on
   the path (the notes say so), and a `.sym` that does not match its
   library's manifest. `llvm-lto` had no comparison with its golden
   (`testresult.sh` missing), now fixed. rackhir (FreeBSD arm64) ran
   `gmake check` on `6285c40`, which has every step 2 commit through 2g:
   295/295 under Stage 0 and Stage 1, Stage 1 and Stage 2 identical.

3. **A complete inventory of the libraries and modules voc supplies.**
   From the sources, not from memory: enumerate every module under the
   voc clone's `src/runtime` (`SYSTEM`, `Heap`, `Files`, `In`, `Out`,
   `Math`, `MathL`, `Modules`, `Oberon`, `Platformunix`/`Platformwindows`,
   `Reals`, `Strings`, `Texts`, `VT100`, as of this writing), every
   library directory under `src/library` (`misc`, `ooc`, `ooc2`,
   `oocX11`, `pow`, `s3`, `ulm`, `v4`), the modules the install actually
   ships (`showdef` on the installed symbol files under
   `/usr/local/sw/versions/voc/git/{2,C}/sym`, which also shows what each
   one exports), and the programs under `src/tools` (`autobuild`,
   `beautifier`, `browser`, `coco`, `HeapDump`, `make`, `ocat`,
   `testcoordinator`, `vmake` - to be classified as library, program, or
   neither). For each module record: name and the directory it lives in;
   what it is for; its imports (so the dependency graph, and so which
   modules can be taken without dragging in others); whether it depends on
   the platform (`Platformunix`, `oocwrapperlibc`, `oocFilesHost`,
   `oocProgramArgsHost`), on the C library, on X11, on zlib, or on the
   size model; whether it is part of a standard (Oakwood, the ooc library
   family) or voc's own; whether it is already in Phase 10's scope; and
   its licence, since poc cannot ship what it cannot legally ship. The
   result is a table kept as a file the plan names, not prose - the
   *complete* list the plan has been missing, with `ulm` and `v4`
   (not yet looked at at all) filled in like the rest. *Done
   2026-09-27*: `doc/voc-module-inventory.md`, all 161 files, with for
   each what voc builds (its `-OC` library is the runtime only), what
   poc's front end makes of it today (`poc -emit-interface` in import
   order against poc-rtl's interfaces: 23 accepted, 34 after the
   language fixes below), and the findings
   step 4 and Phase 19 start from. Most of the library stops on what poc's
   `Platform`, `Files` and `Modules` lack; ten modules hold voc's inline
   C; s3's zlib is Oberon, not C; and six language points came up, among
   them a conformance bug (a one-character string constant compared
   with a `CHAR`, and a character constant used as a string, `Oberon2.pdf`
   §3). A trap in the checker on a record whose base came from a module
   that could not be imported was fixed on the way
   (`semantic-reject-unresolved-record-base`). The user's decisions on
   the language points (2026-09-27): the §3 rule fixed both ways; text
   after `END M.` ignored; a 16-digit hexadecimal constant above
   `MAX(HUGEINT)` taken as a 64-bit pattern, as voc does, unless
   `-strict`; `LONG` of a `CHAR` stays an error; `POINTER [1] TO` is not
   adopted (a port uses `SYSTEM.ADDRESS`); a function with an empty body
   stays an error (a port removes `ulmSYSTEM`'s two). `tools/voc-inventory/
   inventory` regenerates the tables (to rerun when poc's runtime or
   front end changes what they say).

4. **Deciding what poc supports.** *Decided with the user 2026-09-27*:
   for now poc offers modules compatible with voc's **runtime** modules
   (`src/runtime`), and everything under `src/library` (`v4`, `ooc`,
   `ooc2`, `oocX11`, `s3`, `ulm`, `misc`, `pow`) moves to Phase 19, to be
   considered after all the other phases, with step 3's inventory as its
   starting point. Of the runtime:
   - **`Heap` is not provided.** Nothing under `library/` imports it; only
     voc's own `Files` and `Modules` do. Most of it is voc's code
     generator's interface to its runtime (`REGMOD`, `REGTYP`, `REGCMD`,
     `INCREF`, `NEWREC`, `NEWBLK`, `InitHeap`), which poc's code
     generator has its own form of; `Lock`/`Unlock` serve voc's
     signal-driven interrupts, `FileCount` is a counter nothing reads,
     `FreeModule` unloads nothing, `TAS` is Ulm's non-atomic
     test-and-set. Its collection and statistics are in
     `GarbageCollectedHeap` already (`Collect`, `LiveBytes`,
     `HeapBytes`, `SetChunkSize`); no thin `Heap` over them (user's
     decision).
   - **Finalization is taken from it**: poc's collector gets `Heap`'s
     `RegisterFinalizer(obj, finalize)`, and poc's `Files` uses it as
     voc's does, so a `File` dropped without `Close` is still closed
     and its buffer written when it is collected.
   - **Everything else in the runtime is made interface-compatible**
     with voc's: `Files`, `In`, `Modules`, `Platform` (the Unix
     variant), `Oberon`, `Reals`, `Texts` and `VT100`; `Out`, `Strings`,
     `Math` and `MathL` already are. `Console` (voc's `library/v4`) and
     `Err` stay as they are.

5. **Implementing the runtime modules.** Each is ordinary Oberon-2 in
   `rtl/llvm`, built into `poc-rtl`, with `["C"]` external procedures
   where voc's has inline C, and written for all four Unix-likes (the
   standing rule for `rtl/llvm`). What each lacks is measured from the
   modules' exports (2026-09-27; a name counts once, whatever its kind).
   Where poc cannot or will not match voc (a Linux-only call, a detail of
   voc's own layout), the difference is decided with the user and
   written down. **Testing**: per substep, compile+link+run+diff fixtures
   compared with the same program under voc, as Phase 9's were. The
   substeps follow the modules' imports (voc's `Texts` imports `Files`,
   `Modules` and `Reals`; `Oberon` imports `Texts` and `Modules`; `Reals`
   needs `Platform.LittleEndian`), each its own commit:

   - **5a. `Platform`** (5 of 46 procedures; the base the rest need):
     files by handle (`OldRO`, `OldRW`, `New`, `Close`, `Read`,
     `ReadBuf`, `Write`, `Seek`, `Size`, `Truncate`, `Sync`, `Rename`,
     `Identify`, `IdentifyByName`, `SameFile`, `SameFileTime`,
     `SetMTime`, `SetFileMTime`, `MTimeAsClock`, the error tests
     `Absent`, `Inaccessible`, `TooManyFiles`, `NoSuchDirectory`,
     `DifferentFilesystems`, `Interrupted`, `TimedOut`,
     `ConnectionFailed`, `Error`), time (`Time`, `GetClock`,
     `GetTimeOfDay`, `Delay`), memory (`OSAllocate`, `OSFree`), the
     signal handlers (`SetInterruptHandler`, `SetQuitHandler`,
     `SetBadInstructionHandler`), `getEnv`, `IsConsole`,
     `MaxNameLength`, `MaxPathLength`; and the types and constants
     `FileHandle`, `FileIdentity`, `LittleEndian`, `NL`,
     `SeekSet`/`SeekCur`/`SeekEnd`, `StdIn`/`StdOut`/`StdErr`.
     **Done (2026-10-02).** Decided with the user: what differs between
     the four systems (open's flags, errno and its values, `struct stat`,
     the clock, signals, NetBSD's renamed functions) is in
     `rtl/llvm/Platform.c`, and poc compiles a module's sibling `.c` with
     it wherever it compiles the module (`doc/llvm-toolchain.md`, "A
     module's part in C"; fixture `llvm-c-part`). An error code is now
     errno's value, as voc's (it was -1; `Files.Delete`/`Rename` too).
     Differences kept: `Write` writes everything and `Delay` sleeps the
     whole time (voc's make one call each); `StdIn`/`StdOut`/`StdErr` are
     exported with `*` where voc's have `-`: voc accepts the read-only mark
     on any declaration but gives it a meaning only on variables and record
     fields (`OPP.CheckMark`), so on a constant it is a plain export, and
     poc keeps rejecting it there (decided with the user 2026-10-02). Fixture
     `llvm-platform-files` (44 checks, against voc, both size models).
   - **5b. `In.Name` and `VT100`** (new: terminal control sequences);
     small, needing nothing else. **Done (2026-10-02).** `In.Name` needed
     nothing: poc's has read a name (Oakwood: "according to the file name
     format of the underlying operating system") since Phase 10, and
     voc's only halts; the gap step 4 listed was a mistake. `VT100` is
     written for poc (voc's is under voc's runtime licence), with voc's
     interface; where voc's garbles a sequence - a count of 10 or more
     cut to its first digit, `DSR` ignoring its argument - poc's writes
     what the procedure describes (user's decision). Fixture `llvm-vt100`
     (every call voc gets right, byte for byte against voc, both size
     models; the differences on their own).
   - **5c. Finalization** in `GarbageCollectedHeap`, from voc's `Heap`
     (`RegisterFinalizer(obj, finalize)`): registered objects are weak
     references, not roots; one unreachable after marking is kept for its
     finalizer, which runs after the collection. A collector change, so
     rackhir runs after it. **Done (2026-10-02).** Decided with the user:
     when the program ends every object still registered is finalized,
     newest first, reachable or not, whether it returns from its main
     module's body or stops at `HALT`, `ASSERT`, a trap or
     `Platform.Exit`: all of them end in C's `exit()`, so the first
     registration hands the collector's `FinalizeAtExit` to `atexit` and
     no trap site changes. voc runs them (`Heap.FINALL`) at the same
     points but `Platform.Exit`, and before a trap's message (poc's come
     after it); a signal (`SIGFPE`) runs none in either. The registered
     objects are a calloc'd table nothing scans; after marking, those left
     unmarked move to a pending table, whose objects are then marked as
     roots, and each finalizer is called after the collection, taken off
     the table first (`GarbageCollectedHeap`, "FINALIZATION"; also
     `FinalizeAll`, voc's `FINALL`). Fixture `llvm-gc-finalize`.
   - **5d. `Files`** (15 of 37 until then): the typed riders (`Read`/`Write` of
     `Bool`, `Byte`, `Bytes`, `Int`, `LInt`, `Real`, `LReal`, `Set`,
     `Num`), `GetDate`, `GetName`, `Purge`, `ChangeDirectory`,
     `SetSearchPath`, `MaxNameLength`, `MaxPathLength`; and 5c's
     finalization of a `File` dropped without `Close`, as voc's does.
     **Done (2026-10-02).** `Files` has voc's whole interface (37
     procedures). Decided with the user, from the Oakwood Guidelines
     (1.2.5): `Read`/`Write`/`ReadByte` take a `SYSTEM.BYTE`, and a `BYTE`
     parameter takes a `CHAR`, a `SHORTINT` (where it is one byte, `-O2`)
     or a `BYTE`, a `VAR` one a `BOOLEAN` too, as voc's (a checker change,
     `doc/language-extensions.md`, "SYSTEM subset"; voc's `INT8` not
     taken); the typed riders write Oakwood's external format under both
     size models (an `INTEGER` 2 bytes, a `LONGINT` 4, little-endian) and
     read it back sign-extended, where voc's `-OC` reads a negative number
     as a large positive one. Every `File` is registered for
     finalization: dropped or left at the end, its stream is closed and a
     never-registered `New` file's temporary file deleted. `GetName` gives
     the name as given, as voc's (a temporary file's is absolute). voc's
     `Delete` of a file it has open answers 2 though it deleted it; poc's
     0. Fixtures `llvm-files-riders` (against voc, both size models, the
     bytes too, and what poc does alone), `semantic-system-byte-params`.
   - **5e. `Modules`** (4 of 9): `Halt`, `AssertFail`, `Free`,
     `res`/`resMsg`, `imported`/`importing`, `BinaryDir`, and `ThisMod`/
     `ThisCommand` in full, as voc (user, 2026-09-27): each module's
     `_init` registers its name and its commands - exported procedures
     with no parameters and no result, as voc's `OPC.RegCmds` picks them -
     so a program finds a module of its own by name and calls a command
     of it by name (`Texts.Load` recreates a text's elements this way;
     a command dispatcher is the other use). poc's `Modules` declares its
     own `Module`, `ModuleName`, `Cmd` and `Command` (voc's are `Heap`'s);
     the registration extends the per-module table `ModuleTable` already
     keeps for the collector. As in voc, a module is found only once its
     `_init` has started, only modules linked into the program exist, and
     `Free` unloads nothing. The cost, to note in the documentation: a
     command is referenced from its module's table, so neither the
     linker nor `-lto` drops an unused one. Code generator work, so
     rackhir runs after it; split in two if the registration grows large.
     **Done (2026-10-02)**, in one step. In a program that contains
     `Modules`, each module's object has a descriptor - its name, the
     names of the modules it imports, and its commands as names and
     addresses - which its `_init` hands to `ModuleTable.RegisterModule`
     right after its imports' `_init` (`LLVMCodeGenerator`, "module
     descriptors"; `ModuleTable.Mod`, "MODULE DESCRIPTORS"). `Modules`
     makes voc's `Module`/`Cmd` records from them when a program first
     looks, so `refcnt` (the listed modules importing it) and `Free`
     (off the list when nothing imports it) are voc's; `Modules` calls
     `NEW`, so a program containing it gets the collector. Differences
     kept: names of up to 255 characters (`ModNameLen` 256; voc's 20);
     commands in declaration order (voc's reverse alphabetical); `Halt`
     and `AssertFail` write to standard error, as poc's traps, with the
     finalizers after; `MainStackFrame` is argv's address. `BinaryDir`
     is voc's search (argument 0, else `$PATH`), `.` and empty parts
     dropped. A module compiled on its own (`-compile`, a library) has a
     descriptor only if `Modules` was in the program it was compiled
     with; poc-rtl's modules all do. Fixture `llvm-modules-commands`.
   - **5f. `Reals`** (new; 10 procedures, the conversions `Texts` uses).
     **Done (2026-10-02).** poc's own code with voc's interface: it reads
     a real's bits as an integer, not bytes at `Platform.LittleEndian`'s
     offsets, so it imports nothing but `SYSTEM`. Differences kept, all
     where voc's answer is wrong or undefined: `Ten`/`TenL` are correctly
     rounded (libc's `strtof`/`strtod` of "1E<e>"; voc's `TenL` squares
     its way up and is off in the last bit for 252 of the exponents
     0..308) and give 10^e for a negative `e`; `ConvertL` writes the
     exact low digits of any number's integer part (voc's goes through a
     `LONGINT`). `ConvertH`/`ConvertHL` write the bytes least significant
     first, as voc's and Ofront's do. Fixture `llvm-reals-module` (against
     voc, both size models, and what poc does alone).
   - **5g. `Texts`** (new; voc's file-based texts, readers, scanners and
     writers, no display: 38 procedures).
     **Done (2026-10-02).** poc's own code with voc's 38 procedures: a
     text is a ring of pieces of files and elements, in Oberon V4's file
     format (and System 3 documents and plain files read); elements are
     stored by their handlers and loaded through `Modules.ThisCommand`,
     an unknown one kept as an alien. Differences kept, all where voc's
     answer is wrong or stops the program (the module's header lists
     them): real numbers written and scanned correctly rounded
     (`RealDigits.Fixed` is new for `WriteRealFix`), a scanned number past
     the range an infinity, a loaded text keeps its fonts, CR LF in a
     plain file one line end when stored, a NIL font the default one,
     an element whose handler does not copy it left out of a copy.
     Fixture `llvm-texts` (against voc, `-O2` only: voc's `-OC`
     `Files.ReadLInt` reads an element's negative length as a large
     positive one, 5d, so its `Load` stops on any text with elements).
     All six modules that import `Texts` or `Oberon` now pass `poc -check`.
   - **5h. `Oberon`** (new; the stub system module: `Log`, `Par`,
     `Time`, `GetClock`).
     **Done (2026-10-02).** poc's own code with voc's interface (`Log`,
     `Par`, `OptionChar`, `GetClock`, `Time`, `GetSelection`): `Par.text`
     holds the program's arguments, each followed by a blank; `Log` echoes
     to standard output what is inserted into it. Differences kept: an
     argument is copied whole (voc's cuts it at 255 characters), and only
     an insertion into `Log` is echoed (voc's also echoes after a deletion
     or a change of looks, writing the text that then stands at those
     positions). Fixture `llvm-oberon` (against voc, both size models, and
     what poc does alone).

6. **Exit gate.** Every runtime module of step 5 builds into `poc-rtl`,
   static and shared, and passes its fixtures at both word sizes on
   Linux and the three BSDs, with `make check` clean on each - the same
   bar as Phase 9 step 9 - and on rackhir (arm64) at the close-out.
   **Done (2026-10-02).** At `bb440e7`, the tree with all of step 5:
   `make check` and `make check-opt2` on atla, and `gmake check` on
   cymoril, artos and alerik, each clean (309 or 312 fixtures per run,
   none failed; Stage 1 and Stage 2 identical on each). 64 bits on atla,
   artos and alerik; 32 bits natively on cymoril (OpenBSD i386) and by
   the i686 fixtures elsewhere, `poc-rtl` static and shared, except on
   artos, whose NetBSD has no 32-bit shared C library (static only, as
   before). rackhir (arm64), the close-out run: `gmake check` clean
   too, Stage 2 included (312 twice, none failed, Stage 1 and Stage 2
   identical; the i686 fixtures skip on arm64, as always). The close-out
   also fixed a type guard as an assignment's target, `v(S) := t`, a
   syntax error until then (`b65777a`, checked on the four gating hosts;
   `000-todo.org`; fixture `llvm-guard-assignment-target`), and moved the
   question of the lowest 32-bit x86 CPU, deferred here from Phase 11, to
   `PLAN.md`'s "Open design questions".

**Testing summary**: steps 1, 3 and 4 are decisions with written
artifacts (tables and a design), verified against the primary sources
they cite; steps 2 and 5 are compile+link+run+diff fixtures; step 6 is
the whole-matrix gate.
