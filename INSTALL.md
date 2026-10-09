# Installing Peaseblossom (poc)

poc, the Peaseblossom Oberon Compiler, is built and installed with GNU make.
This file says how: from a release tarball (section 2), which is also the
way to install poc on any Linux distribution or BSD that has no package
for it; from the git repository (section 3); and into a place other than
`/usr/local` (section 4). Section 5 is the operating systems' packages. The User's Guide
(`doc/users-guide.md`) is how to use poc once it is installed;
`doc/developer/DEVELOPER.md` is how to work on it.

## 1. What you need

poc writes LLVM IR and hands it to `clang`, which compiles and links it,
both when poc is built and every time poc builds a program. So `clang` must
be on `PATH`, at run time too. Any clang from 19 on does.

| System | Tested on | Install first |
|---|---|---|
| Linux | Fedora 44, x86_64 | `clang`, `make` (`dnf install clang make`) |
| FreeBSD | 15.1, amd64 and arm64 | `gmake` (clang is in the base system) |
| OpenBSD | 7.9, i386 and amd64 | `gmake` (clang is in the base system) |
| NetBSD | 11.0, amd64 and i386 | `clang` and `gmake` from pkgsrc (`pkgin install clang gmake`) |

On NetBSD, clang must come from pkgsrc's packages for the system's own
release: pkgin's repository (`/usr/pkg/etc/pkgin/repositories.conf`) should
end in `11.0/All` on NetBSD 11.0. A clang from the 10.0 packages compiles
for `x86_64-unknown-netbsd10.0` unless told otherwise (`clang
-print-target-triple` shows it), and poc, built or installed for 11.0, then
finds none of its runtime: every program fails with "unknown imported
module", and a note that `poc-rtl` has the module for
`x86_64-unknown-netbsd11.0`. Point the repository at `11.0/All` and run
`pkgin update && pkgin full-upgrade`; until then, `poc -target
x86_64-unknown-netbsd11.0` works.

GNU make is `make` on Linux and `gmake` on the BSDs; the commands below say
`make`. poc has been run only on the systems above; elsewhere it may work,
but nothing has checked it.

Optional: `glibc-static` on Linux, for `poc -static`; gdb 7 or later, or
lldb, for `poc -g` (on OpenBSD the `gdb` package's `egdb`); on NetBSD,
lld, for `poc -lto` (`pkgin install lld`).

## 2. From a release tarball

A release is `peaseblossom-<version>.tar.gz`, from
<https://github.com/tkurtbond/peaseblossom/releases>, with its SHA-256 sum
(`.sha256`) and sometimes a GPG signature (`.asc`). The tarball carries poc's
own LLVM IR, its *seed*, so clang alone builds poc from it: no other Oberon
compiler is needed.

    sha256sum -c peaseblossom-0.5.0.tar.gz.sha256   # Linux, FreeBSD
    cksum -a sha256 peaseblossom-0.5.0.tar.gz       # OpenBSD, NetBSD: compare
                                                    # with the .sha256 file
    gpg --verify peaseblossom-0.5.0.tar.gz.asc      # if there is one
    tar xzf peaseblossom-0.5.0.tar.gz
    cd peaseblossom-0.5.0
    make installable             # builds everything make install copies
    make check-install           # optional: installs a copy in a scratch
                                 # directory, builds and runs programs
                                 # with it, and removes it
    make install                 # as root, for /usr/local

`make installable` builds poc three times: from the seed (Stage 0), then
with itself (Stage 1, and Stage 2, whose output must be Stage 1's), and
poc's runtime library, `poc-rtl`, for both size models, with and without
debugging information. It takes a few minutes. `make install` copies
Stage 2 and the runtime. It builds whatever is missing first, as root if run
as root, so build as yourself beforehand. (A plain `make` builds only Stage
0, the quick build for working on poc.)

The seed is for 64-bit hosts (x86_64, amd64, aarch64) and for 32-bit x86
OpenBSD and NetBSD. On any other host the tarball cannot build poc by itself;
build it from git (section 3) with an Oberon compiler.

**On any Linux distribution, or any of the BSDs.** There is no binary
tarball of poc, and none is needed: the release tarball is the same for
every system, and building from it is the way to install poc anywhere
without a package of its own. One tarball serves every system because
everything built from it is built on the system it will run on:

- **No dependence on the system's C library version.** poc and its
  runtime are compiled against the C library that is there, so a newer
  system's glibc version is not needed. By default the runtime is linked
  into every program poc builds, so those programs need the same C
  library and nothing else.
- **No dependence on the vendor in clang's triple.** The runtime is filed
  under the host's own target triple, whatever clang calls it
  (`x86_64-redhat-linux-gnu` on Fedora, another name elsewhere). poc
  refuses a runtime filed under another triple, so one built elsewhere
  would not do.

What the system needs is what section 1 lists: GNU make, and a clang
from 19 on, as `clang` on `PATH`. A distribution that installs its clang
only under a versioned name, such as `clang-19`, needs a link named
`clang` to it, on `PATH` before any older clang. Then build and install
as above, with `PREFIX` as section 4 says for where it goes: a home
directory needs no root.

The BSDs' packages (section 5) are built from this same tarball, so on
FreeBSD, OpenBSD and NetBSD it is checked at every release. Among Linux
distributions only Fedora is checked. The build is the same on any
other, but nothing has tried one.

## 3. From the git repository

    git clone https://github.com/tkurtbond/peaseblossom.git
    cd peaseblossom

A checkout has no seed (it is made only for a release), so the first poc is
built by another compiler, one of:

- **Vishap Oberon (voc)**, which poc was first written with. `make` looks
  for it in `/usr/local/sw/versions/voc/git/bin`; elsewhere, name its
  `bin` directory:

      make VOC_BIN_DIR=/opt/voc/bin

  voc's own programs need its `lib` directory, which `VOC_LIB_DIR`
  names when it is not `$(VOC_BIN_DIR)/../lib`.

- **A poc already installed** (from a tarball or a package):

      make BOOTSTRAP_POC=/usr/local/bin/poc

Then, as for a tarball:

    make installable
    make check-install
    make install

`make check`, the whole test suite, needs voc: it compares poc with it.
`doc/developer/DEVELOPER.md` says more.

**Without installing.** `make` leaves a working poc in `build/bin/poc`,
with its runtime in `build/lib/poc`, where it finds it: Stage 0, built by
voc (or `BOOTSTRAP_POC`). `make installable` adds `build/stage2/bin/poc`,
with its runtime in `build/stage2/lib/poc`, the one that is installed.

## 4. Where it goes, and installing elsewhere

`make install` takes the usual variables:

| Variable | Default | What goes there |
|---|---|---|
| `PREFIX` | `/usr/local` | the base of the others |
| `BINDIR` | `$(PREFIX)/bin` | `poc` |
| `LIBDIR` | `$(PREFIX)/lib` | `poc/<triple>/{O2,OC,O2-g,OC-g}/`: the runtime, `poc-rtl`, for each size model, plain and with debugging information |
| `MANDIR` | `$(PREFIX)/share/man`; `$(PREFIX)/man` on OpenBSD and NetBSD | `man1/poc.1` |
| `DOCDIR` | `$(PREFIX)/share/doc/peaseblossom` | `README.md`, `LICENSE`, the User's Guide and the Reference Guide; in `html/` and `pdf/`, those guides and poc(1), from a release tarball or `make doc` |
| `DESTDIR` | empty | prefixed to every path above when the files are written, for staging |

`<triple>` is clang's target triple for the host (`clang -dumpmachine`),
such as `x86_64-redhat-linux-gnu` or `x86_64-unknown-freebsd15.1`.

**poc finds its runtime beside itself**, as `../lib/poc` from the directory
it is in (following symbolic links to poc). So keep `LIBDIR` at
`$(BINDIR)/../lib`, which the defaults are. If you must put it elsewhere,
every use of poc needs `POC_LIBRARY_PATH=$(LIBDIR)/poc` in the environment
(`make install` reminds you).

Give `make uninstall` the same variables as `make install`; it removes what
was installed, and leaves any other library installed beside the runtime.
`make check-install` always uses a scratch directory of its own, whatever
the variables say.

Some ways to use them:

- **In your home directory**, no root needed:

      make install PREFIX=$HOME/local
      export PATH=$HOME/local/bin:$PATH
      export MANPATH=$HOME/local/share/man:   # $HOME/local/man on OpenBSD, NetBSD

- **In a directory of its own**, such as `/opt`, so that removing it is
  `rm -r`:

      make install PREFIX=/opt/peaseblossom

  Several versions can be installed side by side this way, one `PREFIX`
  each; each poc uses its own runtime (a runtime from another version is
  refused).

- **In `/usr`**, as a distribution would:

      make install PREFIX=/usr

- **Staged**, to make a package or copy the files elsewhere: `DESTDIR` is
  where the files are written, `PREFIX` where they will be:

      make install DESTDIR=/tmp/stage PREFIX=/usr/local

  A program poc builds records where it found `poc-rtl`'s shared library
  (`-shared-libraries`), so build programs with poc in its final place,
  not with the staged copy.

- **A symbolic link** to poc from a directory on `PATH` works: poc follows
  it to find its runtime.

      ln -s /opt/peaseblossom/bin/poc /usr/local/bin/poc

## 5. Packages

`packaging/` has a package for each system, each built from the release
tarball. They install poc into the system's usual places (`/usr/bin` and
`/usr/lib/poc` on Fedora, `/usr/local` on FreeBSD and OpenBSD, `/usr/pkg` on
NetBSD), and need clang: the base system's on FreeBSD and OpenBSD, a
dependency on Fedora and NetBSD.

| System | Package | Built with |
|---|---|---|
| Fedora | `packaging/fedora/peaseblossom.spec` | `rpmbuild` or `mock` |
| FreeBSD | `packaging/freebsd/lang/peaseblossom` | the ports tree, or `poudriere` |
| OpenBSD | `packaging/openbsd/lang/peaseblossom` | the ports tree (`mystuff/`) |
| NetBSD | `packaging/pkgsrc/lang/peaseblossom` | pkgsrc |

None of them is in its system's own collection yet, so each is installed
from a release (below) or built locally; `doc/developer/DEVELOPER.md`,
"Building the packages", has the commands for building one.

### Installing a release's package

Each release also carries a package for each system in section 1, built
from its tarball and named for the system release and architecture it is
for. Check the file against the release's `SHA256SUMS`, as for the
tarball (section 2), then install it as root:

| System | Install |
|---|---|
| Fedora 44, x86_64 | `dnf install ./peaseblossom-0.5.0-1.fc44.x86_64.rpm` |
| FreeBSD 15.1, amd64 | `pkg add ./peaseblossom-0.5.0-freebsd15.1-amd64.pkg` |
| FreeBSD 15.1, arm64 | `pkg add ./peaseblossom-0.5.0-freebsd15.1-arm64.pkg` |
| OpenBSD 7.9, i386 or amd64 | `pkg_add -D unsigned ./peaseblossom-0.5.0.tgz`, under that name (below) |
| NetBSD 11.0, amd64 | `pkg_add ./peaseblossom-0.5.0-netbsd11.0-amd64.tgz`, with pkgsrc's clang for 11.0 installed first (`pkgin install clang`; section 1) |
| NetBSD 11.0, i386 | `pkg_add ./peaseblossom-0.5.0-netbsd11.0-i386.tgz`, with pkgsrc's clang for 11.0 installed first, as for amd64 |

OpenBSD's `pkg_add` refuses a package file not named for the package
itself, `peaseblossom-<version>.tgz` ("Package name is not consistent"),
and the release's name has the system in it so that the files can be
told apart. So give the file the package's name as you download it,
the `i386` one or the `amd64` one:

    ftp -o peaseblossom-0.5.0.tgz \
      https://github.com/tkurtbond/peaseblossom/releases/download/v0.5.0/peaseblossom-0.5.0-openbsd7.9-i386.tgz
    pkg_add -D unsigned ./peaseblossom-0.5.0.tgz

`-D unsigned` is needed because the package is not signed with
`signify(1)`; the release's `SHA256SUMS` is signed with GPG instead. On
any other system release or architecture, build poc from the tarball
(section 2).
