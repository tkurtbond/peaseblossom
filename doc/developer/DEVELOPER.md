# Working on Peaseblossom

How poc is built and tested while it is being worked on, how a change is
checked before it is committed, how the operating systems' packages are
built, and how a release is made. `INSTALL.md` is building and installing
for a user; `AGENTS.md` holds the project's standing decisions (the
language, voc, the hosts), and `PLAN.md` the roadmap.

## 1. The tree

| Directory | What |
|---|---|
| `src/front/` | the front end: scanner, parser, checker, symbol files (`src/front/README.md`) |
| `src/back/llvm/` | the LLVM back end and `LLVMToolchainDriver`, which runs clang |
| `src/back/vax/` | the VAX/VMS back end, to come (Phases 15-18) |
| `src/driver/` | `Poc.Mod` (the command), `Libraries.Mod`, `Version.Mod` |
| `rtl/llvm/` | the runtime, the library `poc-rtl`; `Platform.c` is its part in C |
| `test/conformance/` | the fixtures, one directory each |
| `test/install/` | `check.sh`, what `make check-install` runs on an installed poc |
| `tools/bootstrap/` | the stages: `stage0` (voc, `BOOTSTRAP_POC` or the seed), `stage1`, `stage2`, `make-seed` |
| `tools/` | also `build-info`, `guide-examples`, `rtl-reference`, `voc-inventory`, `bench`, and for a release `set-version`, `check-hosts`, `release-files` (section 7) |
| `doc/` | the user's documents: the guides, `poc.1`, `examples/`; `doc/README.md` lists everything |
| `doc/developer/` | this file and the current design: the language extensions, the bootstrap, the toolchain |
| `doc/research/` | the surveys and inventories behind decisions, and background notes |
| `doc/history/` | the project's history, Phase 11's inventory, and `phases/`, the closed phases |
| `packaging/` | the Fedora, FreeBSD, OpenBSD and pkgsrc packages (section 6) |
| `build/` | everything made; `make clean` removes it |

## 2. Building

poc is written in Oberon-2 and built in stages (`PLAN.md`, "Bootstrap
terminology"):

| Stage | Built by | Command | Result |
|---|---|---|---|
| 0 | voc, a poc (`BOOTSTRAP_POC`), or clang from a tarball's seed | `make` | `build/bin/poc`, `build/lib/poc` |
| 1 | Stage 0 | `make stage1` | `build/stage1/bin/poc` |
| 2 | Stage 1, compared with Stage 1's output | `make stage2` | `build/stage2/bin/poc` |

`make` is the quick loop: Stage 0 and poc-rtl for both size models. `make
installable` builds what `make install` copies (Stage 2 and poc-rtl's four
copies), `make seed` the bootstrap seed (`build/seed`, section 7), and `make
clean` removes `build/` and what the fixtures left (`clean-build`,
`clean-tests`).

`make doc` (or `doc-html`, `doc-pdf`) makes the User's Guide, the Reference
Guide, poc(1) and the documents in `doc/developer/` as HTML and PDF, in
`build/doc/html` and `build/doc/pdf`. It needs pandoc (from GitHub's
Markdown, so they read as GitHub shows them), xelatex with the DejaVu fonts
(`DOC_MAIN_FONT`, `DOC_MONO_FONT`), mandoc for poc(1)'s HTML and groff for
its PDF. The PDFs are US Letter with 1-inch margins; `tools/doc/pdf.lua`
gives a wide table's columns widths, breaks code lines longer than a line
(after a `↪`), and lets long names and paths in code break. Section 7 puts
them all in the tarball; `make install`, and so each package, installs only
the guides' and poc(1)'s, when they are there.
voc is
found as `INSTALL.md` says (`VOC_BIN_DIR`). poc is built with voc's `-OC`
and stays at `-OC` in every stage, because it needs an 8-byte `LONGINT`.

Rules for poc's own source (`AGENTS.md` has the reasons):

- It is strict `Oberon2.pdf`: `make check-strict` compiles all of `src/`
  with `poc -strict`, which rejects every extension.
- It must also type-check under `-O2`: no literal or constant wider than
  32 bits.
- Names are descriptive (`GarbageCollectedHeap`, not voc's terse style).
- voc 2.1.0 has bugs that bite poc's source; `doc/developer/bootstrapping-with-voc.md`
  lists them with their workarounds. Check there before puzzling over an
  error that looks wrong.

The version is in `src/driver/Version.Mod` and nowhere else (0.x.y: the
minor number for features, the patch number for fixes). `tools/build-info`
writes `build/gen/BuildInfo.Mod` with the commit on every build, so `poc
-version` names it, with `-dirty` for a tree with changes.

## 3. Testing

| Command | What |
|---|---|
| `make test` | every fixture, under Stage 0: the quick loop |
| `test/run-tests.sh <name>...` | the fixtures named |
| `make test-llvm` (and `-lexer`, `-parser`, `-semantic`, `-modules`, `-layout`, `-misc`) | one group |
| `make check` | `make test`, every fixture under Stage 1, `make stage2` (the fixed point) and `make check-strict`; reports every failure |
| `make check-opt2` | everything built at `-opt 2` |
| `make check-lto` | the fixtures with `-lto` (not a gate) |
| `make check-install` | installs into a scratch directory and runs `test/install/check.sh` with only that poc and clang |
| `make check-seed` | poc built from the seed builds the same Stage 1 as poc built by voc |
| `make distcheck` | the release tarball builds without voc and passes `check-install` |

**A fixture** is a directory `test/conformance/<name>/` whose name begins
with its group (`lexer-`, `parser-`, `semantic-`, `module-`, `layout-`,
`llvm-`, `oc-`, `poc-`, `doc-`, ...). It has:

- `test.sh`, which starts with `. ../../testenv.sh` (it puts poc and voc on
  `PATH`), writes what it finds to `result`, and ends with `.
  ../../testresult.sh`, which compares `result` with `expected`. Without
  that last line a fixture passes whatever happens.
- `expected`.
- Its sources, as `*.mod`.
- If it builds an executable, a line for it in `.gitignore`
  (`test/conformance/<name>/<name>`), added with the fixture.

A fixture that needs a tool a host may lack (a debugger, mandoc) prints
`PASSED (skipped): ...` and exits 0 there (`llvm-debug-info`,
`doc-poc-man-page`). A fixture that calls C declares C's `int` as
`SYSTEM.INT32` and `size_t` as `SYSTEM.ADDRESS`, never `LONGINT`, which is
8 bytes under `-OC`. Run a new test program under `ulimit -v` and
`timeout` until it is known to stop.

**Generated documentation.** Every example in the User's Guide is a file
under `doc/examples/`, checked by `tools/guide-examples` (fixture
`doc-users-guide`); after a change to what poc prints, run
`tools/guide-examples update`. The Reference Guide's chapter on the
runtime is generated from `rtl/llvm` (fixture `doc-reference-guide`); after
changing a runtime module's interface or comments, run `tools/rtl-reference
update doc/reference-guide.md rtl/llvm <scratch dir>` with `build/bin` on
`PATH`. `poc(1)` must lint clean with `mandoc -T lint -W warning` (fixture
`doc-poc-man-page`), and every option poc accepts must be in the usage
text, `poc(1)` and the Reference Guide (fixture `doc-poc-options`).

## 4. Before a commit: the hosts

A change is checked on four hosts before it is committed:

| Host | System | Runs |
|---|---|---|
| atla | Fedora, x86_64 | `make check`, and `make check-opt2` |
| cymoril | OpenBSD 7.9, i386 | `gmake check` |
| artos | NetBSD 11.0, amd64 | `gmake check` |
| alerik | FreeBSD 15.1, amd64 | `gmake check` |

Add `check-install` when a change touches installing, and `check-seed` when
it touches the bootstrap. A fifth host, rackhir (FreeBSD 15.1 arm64,
emulated and slow), checks commits already pushed: after a change where
the architecture matters (calls, arithmetic, memory layout, the runtime's C
calls, the collector) and at the end of each phase. What it finds is fixed
in a later commit.

`tools/check-hosts` (`make check-hosts`) runs these checks on every host
at once and prints one summary. This host runs `make check check-opt2`
in the tree. Every other host gets a fresh copy of the tree in
`~/poc-bsd`, uncommitted changes included, and runs `gmake check` there.
Each host's output goes to `build/check-hosts/<host>.log`, and the exit
status is 0 only if every host passed:

    tools/check-hosts                          # atla, cymoril, artos, alerik
    tools/check-hosts -t check-install -t check-seed   # also these, on each
    tools/check-hosts -c HEAD rackhir          # a commit, on rackhir

`-t` adds a target to every host's run. `-c` copies a commit (`git
archive`) instead of the tree, as rackhir's check wants, and can't be used
on this host. Through make, the same are `CHECK_TARGETS`, `CHECK_COMMIT`
and `CHECK_HOSTS`. By hand, a host's check is:

    git ls-files -z --cached --others --exclude-standard | xargs -0 tar -cf - \
      | ssh cymoril 'mkdir -p ~/poc-bsd && tar -xf - -C ~/poc-bsd'
    ssh cymoril 'cd ~/poc-bsd && gmake check'

voc and its libraries are at the same paths on every host;
`test/testenv.sh` puts them on `PATH` and `LD_LIBRARY_PATH` itself, as a
non-interactive `ssh` does not. Do not change the tree on atla while its
`make check` runs: the check rebuilds and reads it as it goes.

## 5. Making a change visible

A change a user can see is described where a user looks: the User's
Guide (`doc/users-guide.md`, how to use poc), the Reference Guide
(`doc/reference-guide.md`, exactly what poc accepts and does), `poc(1)`
(`doc/poc.1`, every option), and for a language extension
`doc/developer/language-extensions.md` with its summary in `AGENTS.md`.
`doc/developer/llvm-toolchain.md` records how poc drives clang.

## 6. Building the packages

Each package is built from a release tarball (`make dist`, section 7),
named in it by version and fetched from the GitHub release; until there is
one, copy the tarball to where the system looks for it, as below. A
tarball already there is used as it is, not fetched again: once the
release is published, move any earlier one of the same name aside (`mv`
it to `.prerelease`), so that `makesum` fetches the published one and
records its sums. Each is then built, installed, checked against the
installed poc with `test/install/check.sh <installed poc> <scratch dir>`,
and removed, and nothing may be left. Installing and removing need root;
the rest does not.

### Fedora (`packaging/fedora/peaseblossom.spec`)

    rpmbuild -ba --define "_sourcedir $PWD/build/dist" packaging/fedora/peaseblossom.spec
    mock -r fedora-44-x86_64 ~/rpmbuild/SRPMS/peaseblossom-<version>-1.fc44.src.rpm

`%check` runs `check.sh` on the build root. `mock` (which needs the `mock`
group) checks that the build dependencies are enough. Without the group it
asks for root's password; after `usermod -aG mock`, `sg mock -c "mock ..."`
has the group before you log in again. Install with `dnf
install <rpm>`, check `/usr/bin/poc`, and `dnf remove peaseblossom`.

### FreeBSD (`packaging/freebsd/lang/peaseblossom`)

The port is an overlay: it can be built outside `/usr/ports`, which must
exist. As yourself, with the tarball in `$HOME/ports-work/distfiles`:

    cd packaging/freebsd/lang/peaseblossom
    V="BATCH=yes PORT_DBDIR=$HOME/ports-work/db DISTDIR=$HOME/ports-work/distfiles \
       WRKDIRPREFIX=$HOME/ports-work/wrk PACKAGES=$HOME/ports-work/packages"
    make $V makesum               # after a new tarball: writes distinfo
    make $V DEVELOPER=yes stage stage-qa check-plist test package
    portlint -AC

`make test` runs `check.sh` on the stage directory. In a clean jail, as
root (`poudriere.conf` needs `FREEBSD_HOST` and `ZPOOL`, and the tarball in
`DISTFILES_CACHE` until the release exists):

    poudriere jail -c -j 151amd64 -v 15.1-RELEASE
    poudriere ports -c -p default -m null -M /usr/ports
    poudriere ports -c -p peaseblossom -m null -M <tree>/packaging/freebsd
    poudriere testport -j 151amd64 -p default -O peaseblossom lang/peaseblossom

poudriere builds as `nobody`: the overlay's directories must be readable by
everyone (a `tar` from a tree with umask 027 is not). Install with `pkg
add`, check `/usr/local/bin/poc`, and `pkg delete -y peaseblossom`.

### OpenBSD (`packaging/openbsd/lang/peaseblossom`)

A ports tree for the release (`ports.tar.gz` and `SHA256.sig` from
`https://cdn.openbsd.org/pub/OpenBSD/<release>/`, checked with `signify`)
can be unpacked anywhere and used as yourself with `PORTSDIR` set. The
framework refuses to run without the X sets installed, even for a port
that uses no X. The port goes in `${PORTSDIR}/mystuff/lang/peaseblossom`
and the tarball in `${PORTSDIR}/distfiles`:

    export PORTSDIR=$HOME/ports-work/openbsd/ports
    cd $PORTSDIR/mystuff/lang/peaseblossom
    make makesum                  # after a new tarball
    make fake && make update-plist  # after a change to what is installed
    make clean=package            # after a new tarball: else the old
                                  # package is kept as it is
    make package && make port-lib-depends-check && make test

`portcheck` refuses a port under `mystuff/`; run it on a copy at
`${PORTSDIR}/lang/peaseblossom`. Copy `distinfo` and `pkg/PLIST` back into
`packaging/`. Install with `pkg_add -D unsigned
$PORTSDIR/packages/<arch>/all/peaseblossom-<version>.tgz`, check
`/usr/local/bin/poc`, and `pkg_delete peaseblossom`.

### NetBSD (`packaging/pkgsrc/lang/peaseblossom`)

A pkgsrc tree (`https://cdn.netbsd.org/pub/pkgsrc/stable/pkgsrc.tar.gz`,
with its `.SHA1`) can be unpacked in your home directory and used as
yourself against the system's `/usr/pkg`. pkgsrc needs its own tools
installed first, as root: `pkgin install digest mktools cwrappers pkglint
checkperms`. The package goes in `pkgsrc/lang/peaseblossom`, the tarball
in `pkgsrc/distfiles`:

    cd ~/pkgsrc-work/pkgsrc/lang/peaseblossom
    make makesum                  # after a new tarball
    make package && make test && pkglint -Wall
    make PKG_DEVELOPER=yes stage-install   # pkgsrc's stricter checks

The PLIST names the host's triple as `${POC_TRIPLE}`; after a change to
what is installed, write it again with `make print-PLIST`, replacing the
triple (`x86_64-unknown-netbsd11.0`) with `${POC_TRIPLE}`. Install with
`pkg_add pkgsrc/packages/All/peaseblossom-<version>.tgz`, check
`/usr/pkg/bin/poc`, and `pkg_delete peaseblossom`.

## 7. Making a release

1. **The version.** `make set-version VERSION=<x.y.z>` (`tools/set-version`)
   sets `number` in `src/driver/Version.Mod`, and the same version in each
   package: `Version` in the spec (with `Release` back to 1),
   `DISTVERSION` in the FreeBSD port, `V` in the OpenBSD port and
   `DISTNAME` in pkgsrc's, and in `INSTALL.md`'s example and the
   Reference Guide's "describes poc <major.minor>". It removes any
   `PORTREVISION`, `REVISION` or `PKGREVISION`, and adds a `%changelog` entry that says only "Update to
   <x.y.z>.", for you to fill in. A library records the version that
   built it, and poc refuses one from another version, so libraries are
   rebuilt.
2. **Check** on the four hosts (section 4), with `check-install` and
   `check-seed` as well:

       tools/check-hosts -t check-install -t check-seed

3. **Commit and push**, then check that commit on rackhir:
   `tools/check-hosts -c HEAD rackhir`.
4. **The tarball**, from that commit, on atla:

       make stage2               # the seed is written by a Stage 2 built from HEAD
       make distcheck            # make dist (build/dist/peaseblossom-<version>.tar.gz
                                 # and .sha256), then builds it without voc and
                                 # runs check-install
       make dist-sign            # .asc, with gpg's default key (GPG_KEY=... for another)

   `make dist` refuses a tree that differs from HEAD, or a Stage 2 built
   from another commit. It runs `make doc` (section 2), and puts the HTML
   and PDF documents in the tarball, as `doc/html` and `doc/pdf`, so that
   a package needs no document tools. Each `make dist` writes a new tarball (tar and
   gzip record times), so run it once, through `make distcheck`, and sign
   and publish that one. A release is signed: the tarball, the tag, the RPM
   and the list of sums, each with the maintainer's key (each asks for its
   passphrase). Working over ssh, gpg-agent's graphical pinentry appears
   on the machine's own screen, not yours. Sign instead in a terminal
   where `GPG_TTY=$(tty)`, through a `gpg` first on `PATH` that runs
   `gpg --pinentry-mode loopback "$@"`, so gpg asks there itself. For
   `rpmsign`, which runs `/usr/bin/gpg`, add `--define "__gpg <that gpg>"`.
5. **Tag** the commit, signed, `v<version>` (the packages' download URLs
   use it):

       git tag -s v0.1.0 -m "Peaseblossom 0.1.0"
       git tag -v v0.1.0
       git push origin v0.1.0

6. **Publish** the tarball with its `.sha256` and `.asc`:

       gh release create v0.1.0 build/dist/peaseblossom-0.1.0.tar.gz{,.sha256,.asc} \
         --title "Peaseblossom 0.1.0" --notes-file <notes>

   and on the project's own site.
7. **The packages.** Each package's checksums (`distinfo`) are of the
   published tarball, so they come after it: make them on each system
   (section 6), with the packing lists if what is installed changed;
   build, install, check and remove each package, and commit them. Sign
   the RPMs, binary and source, with `rpm-sign` (`%_openpgp_sign_id` set
   to the key's fingerprint in `~/.rpmmacros`, or given with `--define`):

       rpmsign --define "_openpgp_sign_id <fingerprint>" --addsign <rpm>...

   Attach the packages to the release, each named for the system it is
   for, with a list of every file's SHA-256 sum, signed:

       peaseblossom-<version>-1.fc44.x86_64.rpm, peaseblossom-<version>-1.fc44.src.rpm
       peaseblossom-<version>-freebsd15.1-amd64.pkg
       peaseblossom-<version>-openbsd7.9-i386.tgz
       peaseblossom-<version>-netbsd11.0-amd64.tgz
       SHA256SUMS, SHA256SUMS.asc   # sha256sum of every file; gpg --armor --detach-sign

   `make release-files` (`tools/release-files`) gathers them in
   `build/release/<version>/`:
   - the tarball's three files from `build/dist`;
   - the RPMs from `~/rpmbuild` (`RPM_DIR`);
   - each BSD package by `scp` from the host that built it, named for that
     host's `uname`. `FREEBSD_HOST`, `OPENBSD_HOST` and `NETBSD_HOST`
     default to alerik, cymoril and artos.

   It refuses to go on until the RPMs there are signed. Sign them in place
   with the `rpmsign` command it prints, then run it again; a file already
   in the directory is kept. It then writes `SHA256SUMS` and signs it
   (`GPG_KEY` as for `dist-sign`). It uploads nothing, but prints the
   command that does:

       gh release upload v<version> --clobber build/release/<version>/*

   Each binary package is for that one system release and architecture;
   on any other, poc is built from the tarball or from `packaging/`.
