# Phase 13 — Packaging, installation, and the User's and Reference Guides

Moved here from `PLAN.md` unchanged on 2026-10-03, once the phase was done
(step 9's record written at the close-out, and step 8's note on the
ports' `distinfo` brought up to date). `PLAN.md` keeps the heading, the
note on the renumbering, the goal, and a list of the steps, so a reference
elsewhere to "`PLAN.md` Phase 13 step N" means step N here.

**Inserted 2026-10-02 (user)**, before the VAX/VMS work: the phases after it
were renumbered, so the old Phases 13-18 are now 14-19. Records of closed
phases (`doc/history/phases/`, `doc/history/phase-11-inventory.md`, `doc/history/project-history.md`,
`doc/research/initializers-and-literals-survey.md`) keep the numbers they were
written with: there, "Phase 13" is today's Phase 14, and so on up to "Phase
18", today's 19. A second renumbering followed the same day, when record
and array literals became Phase 14 (user, 2026-10-02): the Phases 14-19
of that first renumbering are now 15-20, so a record written between the
two (`doc/history/phases/phase-12.md`) means today's 15-20 by its 14-19.

**Goal**: make poc something a person who did not build it can install
and use, on Linux and the three BSDs. That means an installed poc that
needs only clang and the C library (not voc, not the source tree), a way
to build it from source without voc, a release that can be downloaded, OS
packages, and the documentation to go with them: a User's Guide (how to
use poc), a Reference Guide (what exactly poc accepts and does), and a
`poc(1)` manual page. Placed before the VAX/VMS backend because it is
about the LLVM backend people can run today, and because writing the
guides is a review of the whole command line and runtime, best done
before a second backend adds to them.

**Decided with the user (2026-10-02)**: a new phase, not a Phase 12 step;
the guides in Markdown under `doc/` (installed to the documentation
directory) plus a `poc(1)` page in mdoc, which Linux's and the BSDs' `man`
all render; and all four of `make install`, a bootstrap seed, a release
tarball and OS packages.

**Explicit non-goals**: packaging for VAX/VMS (a VMS kit belongs with the
VAX phases); Windows and macOS; a stable binary interface between poc
releases (a library built by one poc version is not promised to link with
another's programs; the module keys of Phase 12 step 2b already refuse a
mismatch).

1. **Version and identity.** A version number for poc, kept in one place
   in the source; `poc -version` prints it with the default target triple
   and size model (and the clang it found). Decide with the user: the
   scheme (e.g. 0.x until the first release meant for others), and
   whether a build from a git checkout adds the commit. Every `.sym`,
   library manifest and object could record the poc version that wrote it;
   decide whether a mismatch is refused, warned about or ignored.
   **Done (2026-10-02).** Decided with the user: 0.x.y, starting at 0.1.0,
   until a release meant for others; a build from a git checkout adds its
   commit; only a library's manifest records the version, and a library
   another version wrote is refused. `src/driver/Version.Mod` holds the
   number. `tools/build-info` writes `build/gen/BuildInfo.Mod`, the commit
   (`-dirty` when tracked files differ, empty with no `.git`), rewriting it
   only when that changes; `make` runs it every time, so a new commit
   rebuilds poc, and each bootstrap stage runs it too, so a stage still
   works alone. `poc -version` (after any `-target`, `-O2`, `-OC`) prints
   `poc 0.1.0 (<commit>)`, the target and size model, and the first line of
   `clang --version` (or that there is none). The manifest's new line is
   `poc <number>`: the number only, not the commit, since every commit
   would otherwise make a developer's libraries unusable, and module keys
   already refuse a changed interface. A library without the line, or
   with another number, is refused with "rebuild it", once per library
   (`Libraries.Load` now remembers a refused manifest, which was said once
   per lookup before, for a wrong triple too), and the note on the import
   it leaves missing points to that. `.sym` files and objects are
   unchanged. Fixture `poc-version`; `poc-usage` has the new usage line,
   and `llvm-libraries` and `llvm-using-modules` mask the manifest's
   version.
2. **What a user has to work with: a walk-through.** Before any code,
   use poc as a newcomer would, from the outside: a one-module program, a
   program of several modules in several directories, a library of the
   user's own (static and shared), a program using it from another
   directory, `-g` and a debugger, a voc program ported to poc, a module
   with a C part. List every rough edge found (where poc writes its
   `.sym`/`.ll`/`.o` files, what an error message assumes, what needs an
   environment variable, what only works from the source tree), and
   decide each with the user: fix in this phase, document, or leave.
   **Done (2026-10-02).** Walked through with only an installed-like
   prefix and the system on `PATH` (no voc, no source tree): one module;
   modules in several directories; a library of one's own, static and
   shared, used from another directory; `-g` with gdb; voc's own test
   programs (`testFiles`, `argTexts`, `md5test`, Lola); a module with a C
   part; a trap. Decided with the user:
   - **Fix in this phase.** `poc <file>` means `-build`, and the
     executable is named after the module unless `-o` says otherwise
     (until now `poc Hello.Mod` printed the usage, and `-build` required
     `-o`). `-build`, `-library` and `-compile` are silent on success
     (`-check` keeps "semantic OK", its answer). `-help`/`--help`/`-h`
     print a short summary on standard output and exit 0, pointing to
     `poc(1)` (they printed the whole usage as an error); and compile
     errors name what is wrong ("undeclared identifier" names it; a type
     mismatch names the types where that is cheap), after an audit of
     every message. `-c-flag <arg>`, repeatable like `-link`, passes
     `<arg>` to clang for a module's `.c` part (`-I`, `-D`). A false "a
     record may not directly contain itself", which stops voc's Lola test
     (`LSB.Mod`; a record's extension reached through pointers while its
     base is still being resolved), fixed first, in a commit of its own.
     *Done (2026-10-02).* `poc <file>`, the executable's default name,
     the silence (93 fixtures' expected outputs lost the line, and 12 that
     dropped it with `tail -n +2` before comparing with voc now take the
     whole output), `-help` (`Poc.Help`), `-c-flag`
     (`LLVMToolchainDriver.AddCFlag`; fixture `poc-c-flag`); the Lola fix
     is `3dc49ce`, with the rule of 6.3 that an extension's fields differ
     from its bases', which poc had never checked. The audit: an error
     about a name now says it, "message: details" (`Diagnostics.
     ErrorAbout`): an undeclared, unexported or redeclared identifier,
     field or module, qualified as written (`undeclared identifier:
     Out.Strng`); a mismatched `END` (`END R, not END Q`). One about types
     names them (`Types.Describe`: a basic type by name, a record by its
     name, `M.R` from another module, the rest by structure, `POINTER TO
     Node`, `ARRAY 4 OF CHAR`): an assignment or `VAR` argument
     (`assignment is not type-compatible: CHAR to INTEGER`), an operator's
     operands (`BOOLEAN and SET`), a call of something not a procedure,
     and a predeclared procedure's wrong argument (`ODD requires an
     integer argument: REAL`). Messages that already say all there is
     (`a VAR parameter requires a variable argument`) are unchanged.
     Fixture `semantic-error-details`; 43 others' expected outputs gained
     only the details.
   - **Step 3.** poc-rtl installed twice per size model: as now, and a
     copy built with `-g` that `poc -g` links, so a debugger sees into the
     runtime while ordinary programs stay small (measured: `-g` leaves the
     code and its speed unchanged, but makes a statically linked program
     about 4 times larger on disk, 31 KB to 125 KB). A shared executable's
     run-time path names each library directory both relative to
     `$ORIGIN` and absolutely; settle what an installed one should have.
   - **Document** (the User's Guide): a build writes each module's
     `.sym`, `.ll` and `.o` in the current directory, as voc does
     (`-output-dir` moves them); the import path is not searched
     recursively; every module is compiled again on each build; `poc
     -library` without `-output-dir` writes `./<triple>/<O2|OC>/`, which
     `-library-path .` finds; a trap names its location only with
     `-trap-location`.
   - **Leave**: voc's library modules (`md5test`'s `ethMD5`) wait for
     Phase 20.
3. **The installed layout and `make install`.** `make install` and `make
   uninstall` with `PREFIX` (default `/usr/local`), `DESTDIR`, and the
   usual `BINDIR`, `LIBDIR`, `MANDIR`, `DOCDIR`, on GNU make (`gmake` on
   the BSDs). It installs the Stage 2 poc (built by poc, so needing no
   `libvoc`), `poc-rtl` for the host triple under both size models, static
   and shared, where poc's default library path already looks
   (`<bindir>/../lib/poc/<triple>/<O2|OC>/`), `poc(1)` and the guides.
   Check against each OS's conventions (`hier(7)`; FreeBSD and OpenBSD
   ports install under `/usr/local`, pkgsrc under `/usr/pkg`), what a
   shared `poc-rtl`'s run-time search path is once installed, and that a
   poc reached through a symbolic link still finds its library. A `make
   check-install` target installs into a scratch `DESTDIR` and runs a set
   of fixtures with only the installed poc: no voc on `PATH`, no source
   tree, no `POC_IMPORT_PATH`.
   **Done (2026-10-02).** Decided with the user: the `-g` copy of a
   library lives beside the plain one, in `<triple>/<O2|OC>-g/`; under
   `poc -g` every base on the library path is searched there first, then
   as usual, and `poc -g -library` (and `-install-library`) writes there,
   so a user's own libraries can have a debug copy too
   (`Libraries.SetDebug`; both copies have the same keys). A library in
   poc's own `../lib/poc` is "installed", and a program linking its shared
   library has it in its run-time path only absolutely
   (`Libraries.IsInstalled`, `LLVMToolchainDriver.AddLibrary`); others keep
   the `$ORIGIN`-relative entry first. Found on the way: a poc reached
   through a symbolic link looked for `../lib/poc` beside the link;
   `Libraries.PocLibraryDir` now follows links (with `readlink`, without
   `-f`). `make install` installs `build/stage2/bin/poc` (a file target
   now, made when missing or older than Stage 1), poc-rtl built by it in
   `build/stage2/lib/poc` under `O2`, `OC`, `O2-g` and `OC-g`, copied by
   `poc -install-library`, and `README.md` and `LICENSE` in `DOCDIR`
   (`share/doc/peaseblossom`); `MANDIR` is `share/man`, or `man` on
   OpenBSD and NetBSD, for `poc(1)` in step 7. An installed poc-rtl is
   0.66 MB a size model, 1.4 MB its `-g` copy. `make uninstall` removes
   poc-rtl's files by its manifests, so other installed libraries stay.
   `make check-install` installs into a `mktemp` `DESTDIR`, runs
   `test/install/check.sh` (a program under `-O2` and `-OC`, `-g` linking
   `O2-g`, a shared link run after moving the executable, a library of
   one's own used from another directory, static and shared, poc through a
   symbolic link, a trap, `-help`) with `PATH` only poc's, clang's,
   `/usr/bin` and `/bin`, then uninstalls and checks no file is left.
4. **The bootstrap seed: building poc without voc.** voc ships generated
   C so that it can be built with a C compiler alone; poc can ship the
   `.ll` it generates for itself (Stage 2's output, under `-OC`, which
   poc's own build uses), so that clang alone builds it. A `.ll` names a
   target (datalayout and triple), so a seed is per target: decide with
   the user which (x86_64 Linux and the three BSDs, i386 OpenBSD and
   NetBSD, aarch64 FreeBSD; or one per architecture, its triple
   substituted at build time, if the IR is otherwise the same - to be
   checked), and whether the seed is kept in git or only in the release
   tarball (a seed is several megabytes; regenerating it on every commit
   to the compiler would bloat the history). `make` then builds from the
   seed when voc is absent, and a `make seed` target regenerates it; a
   fixture checks that a seed-built poc reaches the same fixed point as a
   voc-built one. `poc-rtl` is built by the seed-built poc, as by any
   other.
   **Done (2026-10-02).** Checked first: poc's IR for itself depends only
   on the word size. Every 64-bit target's (x86_64 Linux and the three
   BSDs, aarch64 FreeBSD) differs from the others only in its `target
   triple` lines and `<M>.-target.<triple>` symbols, and so does each
   32-bit x86 BSD's; i686 Linux's also lacks the BSDs' stack realignment.
   (On the way: aarch64 got x86_64's `target datalayout`, poc having had
   one string per word size. clang takes the target's own over a module's,
   so no build showed it; fixed after the step's commit:
   `LLVMTypes.DataLayout` has x86_64's, 32-bit x86's and aarch64's (FreeBSD
   clang 19's), and no line for an architecture poc has not been run on;
   `stage0-seed` drops the seed's line; fixture `llvm-datalayout`.) Decided
   with the user: two seeds by word size, and the seed only in the release
   tarball, never in git. `make seed` (`tools/bootstrap/make-seed`) has
   the Stage 2 poc write `seed/64` (for `x86_64-unknown-linux-gnu`) and
   `seed/32` (`i386-unknown-openbsd`) under `-OC`, 30 modules each, 6.7
   MB (1.0 MB gzipped), with `TRIPLE` and `VERSION`, and checks that the
   triple is in each module only twice. `tools/bootstrap/stage0-seed`
   replaces it with `clang -dumpmachine`'s, compiles each module as poc
   would (`-fPIC`, `-O2`, or `-O0` for 32-bit x86) with
   `rtl/llvm/Platform.c`, and links `build/bin/poc`; another word size, or
   a 32-bit x86 other than OpenBSD's and NetBSD's, is refused.
   `tools/bootstrap/stage0` now chooses: `BOOTSTRAP_POC`, a poc already
   built (an installed one), compiles poc (`stage0-poc`), which lets a
   developer drop voc too; else the seed, if there is one; else voc; else
   it says which three it lacks. (Step 5 moved `make seed`'s output to
   `build/seed`, so that a top-level `seed/` is only a tarball's, and put
   the seed before voc, so a tarball always builds from its own.) `make check-seed` builds a Stage 0 from
   the seed and a Stage 1 with it in `build/seedcheck`, and compares that
   Stage 1's output with the voc-built Stage 1's: identical.
5. **The release tarball.** `make dist` writes
   `peaseblossom-<version>.tar.gz`: the source, the seed, the generated
   documentation, `LICENSE` and the README, but no test outputs or build
   products. `make distcheck` unpacks it in a scratch directory, builds
   it without voc, installs it into a scratch `DESTDIR` and runs `make
   check-install`; it must pass on atla and each gating VM (and rackhir
   at the close-out). Decide with the user where releases are published
   (GitHub releases on the project's repository, presumably) and whether
   they are signed.
   **Done (2026-10-02).** Decided with the user: a release is published
   as a GitHub release of `github.com/tkurtbond/peaseblossom` and on the
   user's own site too; it always has the tarball's SHA-256, and a GPG
   signature when the person releasing chooses to make one (`make
   dist-sign`, `gpg --armor --detach-sign` with the default key or
   `GPG_KEY`, into `<tarball>.asc`). A release: commit, `make check` on
   the gating hosts, `make stage2 distcheck` (which makes the tarball
   from HEAD), optionally `make dist-sign`, tag `v<version>`, and attach
   the tarball, `.sha256` (and `.asc`) to the GitHub release and the site.
   `make dist`
   writes `build/dist/peaseblossom-<version>.tar.gz` (3.1 MB) and its
   `.sha256`: HEAD's tracked files by `git archive` (so no build products
   or test outputs), the seed as `seed/`, and `COMMIT`, which
   `tools/build-info` reads where there is no `.git` (and it now takes a
   commit only from the tree's own repository, not one it was unpacked
   inside), so a tarball's poc names its commit. It refuses unless the
   tracked files are HEAD's and the Stage 2 poc that writes the seed names
   HEAD's commit. `make distcheck` unpacks it in a `mktemp` directory and, with
   `VOC_BIN_DIR` pointing nowhere, runs `make check-install` there: Stage
   0 from the seed, Stages 1 and 2, poc-rtl, install and the install
   checks.
6. **The User's Guide** (`doc/users-guide.md`): installing (packages,
   tarball, from git); a first program; the command line, task by task
   (building a program, compiling separately, `-O2`/`-OC`, `-opt`, `-g`,
   `-static`, `-link`, libraries and the library path, `-strict`,
   `-range-checks`, `-trap-location`); modules, imports and where poc looks
   for them; what a trap looks like and what each exit status means;
   debugging with gdb and lldb; calling C (`["C"]` procedures, a module's
   `.c` part); the runtime modules, with a short example each; moving a
   program from voc (what poc does differently, from `AGENTS.md` and the
   module headers). Every example in it is a file the test suite builds
   and runs (a fixture that extracts them, or the examples kept as files
   the guide includes), so the guide cannot go stale silently.
   **Done (2026-10-02).** `doc/users-guide.md`, eleven sections, the
   programs as files under `doc/examples/` (one directory per session).
   `tools/guide-examples check|update` reads two HTML-comment marks
   before a fenced block: `example: <file>` (the block must be the file)
   and `run: <dir>` (each `$ ` line runs, in one shell, in a fresh copy
   of the directory, and the other lines must be what they print);
   `update` writes the new output into the guide for its author to read.
   The fixture `doc-users-guide` runs `check`. The gdb session is shown,
   not run (no debugger on every host); the installing section's commands
   are not run either. `make install` puts the guide in `DOCDIR`. Writing
   the guide found and fixed: `-check` did not search libraries (so a
   module importing `Out` failed; it now reads a library's `.sym` files,
   though still no sources, and its "not found" notes name the library
   path), `-output-dir` with a build did not
   make the directory (now every command makes it, as `-library` did,
   and only one that cannot be made is an error), and a module missing its `END` name got a second
   error naming an empty one.
7. **The Reference Guide** (`doc/reference-guide.md`): what poc accepts
   and does, exactly, as a companion to `Oberon2.pdf`, which it refers to
   and does not reproduce. The basic types'
   sizes and ranges under each size model and target; every choice the
   report leaves to the implementation; every extension, from
   `doc/developer/language-extensions.md`, and what `-strict` rejects; `SYSTEM`; the
   predeclared procedures' exact rules where poc pins them down (constant
   expressions, overflow, `DIV`/`MOD`, `ENTIER`, array assignment, `FOR`);
   the trap statuses; each runtime module's interface, procedure by
   procedure (from the modules' own comments, which this step checks and
   completes), and where it differs from voc's; every option and
   environment variable; the formats a user may meet (`.sym`, library
   manifests). And `poc(1)` (`doc/poc.1`, mdoc): the synopsis, every
   option, the environment, the files, the exit statuses, examples and
   pointers to the guides; `mandoc -T lint` clean, and checked to render
   with `man` on each host. Decided (user, 2026-10-02): where
   `doc/developer/language-extensions.md` and the Reference Guide cover the same
   extension, `doc/developer/language-extensions.md` is the design document (why,
   what was considered, how it is built) and the Reference Guide documents
   the extension as actually implemented (what a program can write and
   what it gets); each points to the other.
   **Done (2026-10-03).** `doc/reference-guide.md`, nine sections: the
   basic types, the implementation's choices, the extensions (each under
   its `doc/developer/language-extensions.md` heading), `SYSTEM`, the exact rules,
   traps and exit statuses, the command line, files and formats (objects'
   keys, `.sym`, a library's directory and manifest), and the runtime
   modules. That last chapter is generated: `tools/rtl-reference
   check|update` (sh and POSIX awk, for the BSD hosts, which have no
   python3) writes, for each module of `rtl/llvm`, its header comment and
   its `poc -show-interface`, each declaration under the comment that
   precedes it in the source, between the guide's `<!-- rtl-reference
   begin/end -->` lines; the fixture `doc-reference-guide` runs `check`.
   Writing it completed the modules' comments (Files, Math, MathL, Texts,
   Platform, GarbageCollectedHeap, Modules, Oberon, In, Out, Err, Args,
   VT100 and the internal ones; a group of declarations shares one
   comment) and found: `-emit-interface` and `-show-interface` did not
   search libraries for imports either (as `-check` until step 6), so an
   rtl module's interface could not be shown; `-check` needs its imports
   compiled, which the User's Guide now says; and two rows of
   `doc/developer/language-extensions.md` that predated D16 (locals zeroed) and
   `-range-checks`. `doc/poc.1` (mdoc) goes to `MANDIR/man1` and the
   guide to `DOCDIR`; `make check-install` renders the installed page
   with `man` and finds both guides.
8. **OS packages.** A Fedora RPM spec (built with `rpmbuild` on atla), a
   FreeBSD port (on alerik, with `poudriere` or `make package`), an
   OpenBSD port (on cymoril), and a pkgsrc package (on artos), each built
   from the release tarball, installed, run through `make check-install`
   against the installed files, and removed cleanly. Their dependencies
   are clang (the version each OS ships) and nothing else at run time.
   Decide with the user whether any is to be submitted upstream (that is
   outside this repository's control and is not this phase's exit
   condition). The packages live under `packaging/<system>/`; `make
   installable` builds everything `make install` copies, for a package's
   build step.
   - **Fedora** (2026-10-03): `packaging/fedora/peaseblossom.spec`. poc-rtl
     goes in `%{_prefix}/lib/poc` (where poc looks, beside its own
     directory, as gcc's files are in `/usr/lib/gcc`), not `%{_libdir}`;
     the `-g` copies keep their DWARF (no debuginfo split, no strip of
     the archives); `libpoc-rtl.so` is not offered as a system Provides.
     `x86_64` only until poc has run on aarch64 Linux. `%check` runs
     `test/install/check.sh` on the build root, which now accepts
     `poc.1.gz`. Built with rpmbuild and in mock (Fedora 44), installed,
     checked against `/usr/bin/poc`, removed with nothing left.
   - **FreeBSD** (2026-10-03): `packaging/freebsd/lang/peaseblossom`
     (an overlay: `poudriere ports -m null -M <dir>/packaging/freebsd`,
     `testport -O`). aarch64 and amd64; base clang, no other dependency;
     a DOCS option. poc-rtl's files are listed from the stage directory
     (their paths hold the host triple, and the modules change with the
     version); poc is stripped, poc-rtl is not. `make test` runs
     `check.sh` on the stage directory. portlint clean; `poudriere
     testport` (15.1 jail) clean; installed on alerik, checked against
     `/usr/local/bin/poc`, removed with nothing left.
   - **OpenBSD** (2026-10-03): `packaging/openbsd/lang/peaseblossom`,
     built from `${PORTSDIR}/mystuff/lang/peaseblossom` (the ports
     framework needs the X sets installed, even for a port without X).
     i386 only, where poc has run; base clang. The packing list names the
     triple `${POC_TRIPLE}` (`x86_64` for amd64, `${OSREV}` for the
     release); `SHARED_LIBS` declares poc-rtl 0.0, the name poc gives it,
     and its `@lib` entries do not add poc-rtl's directories to
     `ldconfig`'s. `make test` is `check-install`. portcheck and
     `port-lib-depends-check` clean; installed on cymoril
     (`pkg_add -D unsigned`), checked against `/usr/local/bin/poc`,
     removed with nothing left.
   - **pkgsrc** (2026-10-03): `packaging/pkgsrc/lang/peaseblossom`,
     against pkgsrc-2026Q3. `NetBSD-*-x86_64` only, where poc has run;
     depends on `lang/clang` (NetBSD's base has none). pkgsrc's compiler
     wrappers include a `clang` that runs gcc, so `pre-build` removes it
     and poc finds the real one. The PLIST names the triple
     `${POC_TRIPLE}`. pkglint clean; installed on artos, checked against
     `/usr/pkg/bin/poc`, removed with nothing left. Found with it:
     `check-install` let `DOCDIR`/`MANDIR` from a package's command line
     reach its inner install (it now sets every directory itself); and,
     with `PKG_DEVELOPER`, that poc's links on NetBSD had no RELRO
     (plain `clang`/`gcc` there add none; the system's programs get it
     from their build systems): poc now passes `-Wl,-z,relro` there, for
     programs and shared libraries (decided with the user; fixture
     `llvm-relro` checks both on every host).
   - The ports' `distinfo` files were first of a tarball made from
     `6cb5eba`; each was made again from the published 0.1.0 tarball
     (`74b2f3e`, step 9).
9. **Exit gate.** From the release tarball, on atla and each gating VM:
   poc builds without voc, `make check` passes with the seed-built poc,
   `make install` and `make check-install` pass, the OS package installs
   and passes; rackhir at the close-out. The User's Guide's examples all
   run, `poc(1)` lints clean (fixture `doc-poc-man-page`, `mandoc -T
   lint -W warning`, skipped without mandoc), and every option `poc`
   accepts appears in both `poc(1)` and the Reference Guide (a fixture
   compares them with the usage text: `doc-poc-options`, which takes the
   options from what `Poc.Mod` compares arguments with; it found
   `-h`/`--help` undocumented, now in all three).
   **Done (2026-10-03): Peaseblossom 0.1.0 is released**, the signed tag
   `v0.1.0` at `7384a60`, published as a GitHub release with the tarball
   (SHA-256 `b07c11cb...`, 3229180 bytes), its `.sha256` and `.asc`, the
   packages, each named for its system (`peaseblossom-0.1.0-1.fc44.x86_64.rpm`
   and the source RPM, both signed with `rpmsign`;
   `-freebsd15.1-amd64.pkg`, `-openbsd7.9-i386.tgz`,
   `-netbsd11.0-amd64.tgz`), and a signed `SHA256SUMS` of every file.
   Before the tag, on the tree it was made from: `make check` on atla,
   cymoril, artos and alerik (326 fixtures in each stage, Stage 1 and Stage
   2 identical) and `make check-opt2` on atla; rackhir's close-out run
   (`gmake check`, `check-seed`, `check-install`). From the published
   tarball, on atla, cymoril, artos and alerik: poc built from the seed
   with no voc, `make check` with that poc as Stage 0, and `make
   check-install`, all passing. Each package was made again from the
   published tarball (`makesum`; `74b2f3e`), built and checked on its
   system (`check.sh` on the stage or build root; portlint and pkglint
   clean), installed as root, checked with `check.sh` against the
   installed poc, and removed with nothing left (`mock` was not run again:
   the shell used was not in its group; it passed at step 8). Found on the
   way: `llvm-libraries` failed one run in five on alerik, from voc's
   `Files` keeping a name relative to the directory current when the file
   was opened (Stage 0 now makes every file by its whole path,
   `f4da4e1`; `doc/voc-bugs/README.md`); and, for `doc/developer/DEVELOPER.md`
   (`7a22273`, `17b2f9f`): `make distcheck` alone makes the tarball that
   is signed (each `make dist` writes a new one), a tarball already in a
   ports tree's distfiles is used rather than fetched, OpenBSD's `make
   package` keeps an existing package, and `rpmsign` needs the key named.

**Testing summary**: steps 1 and 2 end in decisions recorded here;
steps 3-5 and 8 are install-and-run checks on each host; steps 6 and 7 are
checked by their runnable examples and the option cross-check of step 9.
