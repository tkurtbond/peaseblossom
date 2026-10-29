# Working on Peaseblossom

How poc is built and tested while it is being worked on, how a change is
checked before it is committed, how the operating systems' packages are
built, and how a release is made. `INSTALL.md` is building and installing
for a user; `AGENTS.md` holds the project's standing decisions (the
language, voc, the hosts), and `PLAN.md` the roadmap.

**The machines named here are the original developer's.** atla is a
Fedora x86_64 workstation, and cymoril, artos, alerik and rackhir are BSD
virtual machines (section 4 lists them). Commands that name them are what
the original developer runs; another developer will have other machines,
other names, and probably other paths, and uses their own in their place.
What the project needs of a setup is in section 4, "With other
machines".

## 1. The tree

| Directory | What |
|---|---|
| `src/front/` | the front end: scanner, parser, checker, symbol files (`src/front/README.md`) |
| `src/back/llvm/` | the LLVM back end and `LLVMToolchainDriver`, which runs clang |
| `src/back/vax/` | the VAX/VMS back end, to come (Phases 15-18) |
| `src/driver/` | `Poc.Mod` (the command), `Libraries.Mod`, `Version.Mod` |
| `rtl/llvm/` | the runtime, the library `poc-rtl`; `Platform.c` and `Directories.c` are its parts in C |
| `test/conformance/` | the fixtures, one directory each |
| `test/install/` | `check.sh`, what `make check-install` runs on an installed poc, and `check-vax.sh`, what `make check-install-vax` runs |
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

poc for VAX/VMS has stages of its own, V1-V3, which run on a VAX
(section 4, `make vax-stages`).

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

The rule (the user, 2026-10-17): anything made with pandoc is made on
atla by `make dist` and put in the tarball, and a build from the tarball
never needs pandoc, which some of the systems poc runs on, the 32-bit
ones especially, do not have. The tarball has the documents as HTML and
PDF (`doc/html`, `doc/pdf`), the VAX/VMS Guide as text (`doc/text`) and
the VAX kits that hold it (`vax/`); `install`, `install-vax` and the
packages take them from there, and `distcheck` builds the tarball with
pandoc out of reach. A new file written with pandoc goes in the tarball
the same way. Only a git checkout needs pandoc, and only for these
files; on a host without it, `make check-install-vax` leaves the guide
out and says so.
voc is
found as `INSTALL.md` says (`VOC_BIN_DIR`). poc is built with voc's `-OC`
and stays at `-OC` in every stage, because it needs an 8-byte `LONGINT`.

Rules for poc's own source (`AGENTS.md` has the reasons):

- It is strict `Oberon2.pdf`: `make check-strict` compiles all of `src/`
  with `poc -strict`, which rejects every extension.
- It must also type-check under `-O2`: no literal or constant wider than
  32 bits. `make check-o2` checks it.
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
| `test/run-tests.sh [-j <n>] <name>...` | the fixtures named, as many at once as the host has processors (or `-j`, or `TEST_JOBS`) |
| `make test-llvm` (and `-lexer`, `-parser`, `-semantic`, `-modules`, `-layout`, `-misc`) | one group |
| `make check` | `make test`, every fixture under Stage 1, `make stage2` (the fixed point), `make check-strict` and `make check-o2`; reports every failure |
| `make check-stage1` | `make check` without `make test`: what the hosts other than atla run |
| `make check-opt2` | everything built at `-opt 2` |
| `make check-lto` | the fixtures with `-lto` (not a gate) |
| `make check-install` | installs into a scratch directory and runs `test/install/check.sh` with only that poc and clang |
| `make check-install-vax` | installs poc and `make install-vax`'s libraries, kits and guide into a scratch directory and runs `test/install/check-vax.sh`, which builds programs for the VAX with that poc alone (no guest); from a git checkout without pandoc, it leaves the guide out (`VAX_GUIDE=no`) and says so |
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

The original developer checks each change on four hosts before it is
committed (their own machines; "With other machines", below, is for
everyone else):

| Host | System | Runs |
|---|---|---|
| atla | Fedora, x86_64 | `make check`, and `make check-opt2` |
| cymoril | OpenBSD 7.9, i386 | `gmake check-stage1` |
| artos | NetBSD 11.0, amd64 | `gmake check-stage1` |
| alerik | FreeBSD 15.1, amd64 | `gmake check-stage1` |

Add `check-install` when a change touches installing, and `check-seed` when
it touches the bootstrap. A fifth host, rackhir (FreeBSD 15.1 arm64,
emulated and slow), checks commits already pushed: after a change where
the architecture matters (calls, arithmetic, memory layout, the runtime's C
calls, the collector) and at the end of each phase. What it finds is fixed
in a later commit.

`tools/check-hosts` (`make check-hosts`) runs these checks on every host
at once and prints one summary. This host runs `make check check-opt2`
in the tree. Every other host gets a fresh copy of the tree in
`~/poc-bsd`, uncommitted changes included, and runs `gmake check-stage1`
there: the suite under the voc-built poc tests voc's build of poc, which
atla's `make check` covers, and the suite under Stage 1 tests the same
source.
Each host's output goes to `build/check-hosts/<host>.log`, and the exit
status is 0 only if every host passed:

    tools/check-hosts                          # atla, cymoril, artos, alerik
    tools/check-hosts -t check-install -t check-seed   # also these, on each
    tools/check-hosts -c HEAD rackhir          # a commit, on rackhir

`-t` adds a target to every host's run. `-c` copies a commit (`git
archive`) instead of the tree, as rackhir's check wants, and can't be used
on this host. Through make, the same are `CHECK_TARGETS`, `CHECK_COMMIT`
and `CHECK_HOSTS`. By hand, a host's check is:

    git ls-files -z --cached --others --exclude-standard | tar -cf - --null -T - \
      | ssh cymoril 'mkdir -p ~/poc-bsd && tar -xf - -C ~/poc-bsd'
    ssh cymoril 'cd ~/poc-bsd && gmake check-stage1'

voc and its libraries are at the same paths on every host;
`test/testenv.sh` puts them on `PATH` and `LD_LIBRARY_PATH` itself, as a
non-interactive `ssh` does not. Do not change the tree on atla while its
`make check` runs: the check rebuilds and reads it as it goes.

### The VAX/VMS development system

From Phase 15, the original developer also has a VAX: SIMH's
`microvax3900` on atla, running VMS 5.5-2H4 with UCX for TCP/IP, at
`192.168.2.20` while SIMH runs, with an unprivileged user `poc` for this
work (`doc/developer/vax-macro32-backend.md` §2). Phase 15 assembles its
fixtures there. The password is kept out of the tree, in
`~/.netrc-poc-vax` (mode 600), or the file `VAX_NETRC` names, apart from
`~/.netrc`, so that a `~/.netrc` other machines need can stay as it is:

    machine 192.168.2.20 login poc password ...
    machine 192.168.2.20 login poc2 password ...

which the tools' expect scripts and curl (`--netrc-file`) read
themselves, so it never appears on a command line. curl takes the first
entry. `tools/vax-do`, `vax-run` and `vax-assemble` take the first account
whose lock is free (`tools/vax-lock.sh`, a lock for each account in
`/tmp`), so with two accounts two runs use the guest at once, each in its
own home directory; `VAX_USER=<login>` pins a run to one account. A
fixture whose guest output names the account, its user name or its home
directory, pins `VAX_USER=poc` (`vax-lib-information`, `vax-library`,
`vax-platform`, `vax-vms-calls`, `vax-vmsdef`). The two
accounts share a UIC group, and so its process names, lock resources and
group logical names: a fixture names its own, so only the same fixture
run twice at once could collide. The FTP server works only in active mode: `curl --netrc-file
~/.netrc-poc-vax -P - ftp://192.168.2.20/` lists the home directory, and in `ftp`, turn passive
mode off first. Send source files in ASCII mode (curl's `--use-ascii`, or
`ascii` in `ftp`): in binary mode VMS stores them as fixed-length 512-byte
records, not as text. Another developer uses their own VAX or SIMH, and names
it the same way.

`tools/vax-assemble <file.mar>...` assembles MACRO-32 there: it copies
each file by FTP, runs `MACRO/OBJECT/LIST` by telnet (expect, reading the
password from that file itself), brings the `.LIS` back beside the
source, deletes its files on the guest, and exits 0 only if every file
assembled without a warning or an error. An object poc wrote,
`<file>.obj`, among the files is converted there and checked by
`ANALYZE/OBJECT` instead (below). `VAX_HOST` names another guest.
`tools/vax-assemble -available` says whether the guest can be used; the
VAX fixtures assemble their `expected-vax.mar` only where it can, and skip
that part elsewhere. Copies are retried, since the guest's FTP server now
and then refuses one ("425"), and so is that check, since a guest busy with
another run can be slow to answer it. A run of `vax-assemble`, `vax-do` or
`vax-run` logs in twice: one FTP session (`tools/vax-ftp.tcl`, a small
client in the expect script itself, kept alive with NOOP) for the copies
there, the copies back and the deletions, and one telnet session for the
commands. A session per step, as at first (with curl), was most of a run's
time on the guest, and the stream of logins it made twice brought the guest
down: UCX 3.1's INETACP failed in kernel mode (bugcheck SSRVEXCEPT, an
access violation at offset 0xAF of a NIL pointer; 2026-10-12 and
2026-10-13).

**poc's objects on the guest** (PLAN.md Phase 18 step 4c;
`doc/developer/vax-object-language.md`, section 15.9). `vax-assemble`,
`vax-do` and `vax-run` take poc's objects, `<name>.obj`, which on Linux
and the BSDs hold the records counted, as VMS keeps them on disk. Each is
copied in binary mode (TYPE I) as `<NAME>.CNT`, which the guest stores as
fixed 512-byte records, and `OBJCONVERT` (`tools/objconvert/
ObjectConvert.Mod`) writes it as `<NAME>.OBJ`, a variable-length record
each, before anything else runs. The converter is built in the account's
`[.OBJCONVERT]` and kept as `[.BIN]OBJCONVERT.EXE`, with
`[.BIN]OBJCONVERT.KEY`, a checksum of the MACRO-32 poc wrote for it,
which `tools/vax-objconvert` writes into `build/objconvert`: a run builds
it again when the key differs, the first run after a change to it or to
`rtl/vax` taking some minutes more. `vax_mar` (`test/vaxfixture.sh`)
gives `vax-assemble` the fixture's objects with the expected `.mar`
files, so every object a VAX fixture's poc wrote is checked by
`ANALYZE/OBJECT` on the guest, whose status is judged as MACRO's is.

The guest sees the expected `.mar` files, the same whichever poc runs the
suite, and poc's objects, the same from every stage of poc, so only `make
test`'s run uses it: `test-stage1`, `check-opt2` and
`check-lto` set `VAX_GUEST=skip`, which skips that part of every VAX
fixture, as on a host without the guest.

`tools/vax-do [-o <dir>] [-get <NAME.EXT>]... [-p <word>] <proc.com> [<file>...]`
runs a DCL command procedure there (PLAN.md Phase 16 step 1): it copies
the procedure and the files in, as their names uppercased, runs
`@<PROC>/OUTPUT=VAXDO.LOG`, with `-p`'s word as its P1, prints the log, copies it and each `-get` file
back into `-o`'s directory (default `.`), and deletes its copies on the
guest. A procedure writes what it has to say to files or to its output,
never to a terminal for the tool to read; it exits with the status
`vax-do` reports. Files go in ASCII mode, but for poc's objects, which
are converted as above.

A fixture runs a DCL procedure of its own on the guest with `vax_do
<proc.com> <expected> [<file>...]` (`test/vaxfixture.sh`). It runs the
procedure with `tools/vax-do` and compares what it printed with
`<expected>`. Where the guest can't be used, or under `VAX_GUEST=skip`,
it says it skipped, as the other guest parts do. Such procedures are named
`guest-<name>.com`, and a hand-written MACRO-32 source in a fixture is
named `hand-<name>.mar`, which `test/testenv.sh` keeps (`vax-hello`,
`vax-build`; Phase 16 step 2).

Where a fixture's failure is a matter of chance, as with ASTs, one run
proves little. With `VAX_REPEAT=<n>` above 1, `vax_do` gives the procedure
n as its P1 (and more time, 600 seconds and 120 a run). A procedure that
honours it builds its programs once and runs them n times: its runs follow
a `RUNS` label, and it calls itself, `@'SELF'/OUTPUT=PASS<i>.TXT RUNS`, for
each. It prints the first run's output, and compares each later one with
it by `DIFFERENCES`, printing only a difference, so `<expected>` still
holds. Redirecting DCL's own output with `DEFINE SYS$OUTPUT` instead
breaks `vax-do`'s `/OUTPUT`. `make test-vax-asts` runs `vax-asts`,
`vax-asts-heap`, `vax-conditions-handlers` and `vax-subprocesses` so,
`VAX_ASTS_REPEAT` times (default 20), two at a time (Phase 17 step 8).

`tools/vax-run <main.mar> [<import.mar>...] <run.dbg>...` runs a program
there under the debugger: it assembles its modules, each named on the
guest by its `.TITLE` (a module given as poc's object, `<module>.obj`,
is converted as above and linked as it is), and `tools/vax-runtime-stub.mar` (stand-ins for
poc's runtime routines, until Phase 16 writes them), links them `/DEBUG`,
the main module first, so the image starts at the program's start, its
`<MODULE>_MAIN`, and runs the image once for each `<run>.dbg`, debugger commands that typically `DEPOSIT` the inputs,
`GO`, and `EXAMINE` what is left; the debugger's output comes back as
`<run>.out`. A fixture's `run-<name>.dbg` is run so, its output compared
with `run-<name>.log`, where the guest can be used (`test/vaxfixture.sh`).
Write a run's inputs and what it expects in `!` comments at its top. Show
values without addresses: `EXAMINE` of a variable, or `EVALUATE
.(%FP-<n>)` for the frame, since a stack address can change. A breakpoint
(`SET BREAK <MODULE>\%LINE <n>`) goes on an instruction, a `; line`
comment having none. A watch stops the program at each change, so the run
needs a `GO` for each; `SET TYPE WORD` (or `BYTE`, `LONG`) before `SET
WATCH` gives its size. `EXAMINE/QUADWORD` shows a `HUGEINT`, and
`EXAMINE/HEXADECIMAL` a `SET`, but `DEPOSIT` takes only decimal, a byte as
signed (`-56` for `200X`), and `-2147483648` only as `-2147483647-1`. A
procedure is tested by `CALL <MODULE>\<label>(<arguments>)`: a constant
goes by value, and a symbol by its address, so a `VAR` parameter's variable
or a `HUGEINT` goes in the stub's `POC_SCRATCH` (`POC_SCRATCH+8` and so on).
The debugger shows R0 as the value returned, so `DEPOSIT R0 = 0` before
calling a proper procedure, whose R0 is otherwise left over. A `FOR` up to
its variable's `MAX` never ends (`Oberon2.pdf` §9.8), nor does the run.
Line numbers in the debugger's output are those of `expected-vax.mar`, so a
change to its reviewer's comment means moving the run's breakpoints and
making the log again. Runs under one account share its home directory,
so each waits for and holds that account's lock on this host while it
uses the guest (`tools/vax-lock.sh`): the VAX fixtures, run in parallel
with the rest, take the guest's accounts one run each at a time. Where
`flock(1)` is, as on Linux, the lock is `flock`'s on
`/tmp/poc-vax-<uid>-<account>.flock`, which the kernel frees when the run
ends, however it ends. Elsewhere it is a directory made by `mkdir`, and a
run that finds one left by a run that was killed stops and names it, to
be removed by hand: taking such a lock over raced, and once let two runs
share an account (2026-10-16).

`make vax-stages` (`tools/bootstrap/vax-stages [-way objects|macro32]
[-to v1|v2|v3] [-install] [-keep]`) is the bootstrap on VMS (`PLAN.md`
Phase 16 step 6 and Phase 18 step 7; `tools/bootstrap/README.md`). `make
vax-v1` cross-compiles poc for the VAX here, into
`build/vax-bootstrap/v1`. `vax-stages` then links that on the guest,
compiles poc there with it (V2) and with V2's image (V3), and compares
their objects, or with `-way macro32` (`make vax-stages
VAX_STAGES_FLAGS='-way macro32'`) their `.mar`, with V1's. It holds the guest's lock for about an
hour and a half, so a VAX fixture run meanwhile waits. `-install` makes
the last stage's image `POC`'s `[.BIN]POC.EXE`. `make vax-kit` writes
the kits a release carries, poc for VAX/VMS as two DCL procedures,
`build/vax-kit/POC-<version>.COM`, poc, and `POC-VMS-<version>.COM`,
`VMSDEF` and `VMSLIB`, and `make check-vax-kit` installs them in
`[.KITCHECK]` on the guest and builds programs with them, for an hour or
more (`tools/bootstrap/README.md`; `vax-macro32-backend.md`, section 21).
The base kit holds the VAX/VMS Guide as text, `VAX-VMS-GUIDE.TXT`
(`tools/doc/plain-text`, so `make vax-kit` needs pandoc). `make
install-vax` installs, beside `make install`'s poc, what the VAX target
needs on Unix: `POCRTL`, `VMSDEF` and `VMSLIB` for `vax-dec-vms` under
both size models in `LIBDIR/poc`, the two kits in
`DATADIR/peaseblossom/vax`, and the guide in `DOCDIR`; `make
uninstall-vax` removes them, and `make check-install-vax` checks both.

`make test-vax-guest-poc` (`tools/vax-guest-poc [-only <regex>]`) runs
the fixtures' compilations under poc on the guest: V1's image, linked
there at the start from V1's objects (`vax-v1 -vax-objects`). The compilations are the programs of
`test/vax-suite.list`, the `vax_mar` lines, and the fixtures that only
run `poc -check`. It compares what poc prints, its status and the files
it writes with the host's poc doing the same for the VAX. `-only` keeps
the fixtures whose names match.

### With other machines

None of this needs those particular machines. What matters is that a
change is checked, as far as you can, on each system and architecture poc
supports before it is committed (Linux and the three BSDs; 64-bit and
32-bit x86, and arm64), and that a release is checked on all of them. A
host, real or virtual, needs:

- clang 19 or later, GNU make (`gmake` on the BSDs), and voc, which
  builds Stage 0 from a git checkout (section 2) and which the crosscheck
  fixtures compare poc with (`INSTALL.md` says where voc is looked for,
  and `VOC_BIN_DIR` names another place);
- for `tools/check-hosts`, `ssh <host>` without a password from the
  machine you work on, and a home directory in which it can make
  `~/poc-bsd`;
- optionally, mandoc, which lints poc(1) (`doc-poc-man-page`), and gdb or
  lldb (`llvm-debug-info`): without them those fixtures skip, still
  passing, so a host without them does not check what they check;
- on the machine that makes the tarball, `make doc`'s tools (section 2):
  pandoc, xelatex with the DejaVu fonts, mandoc and groff.

Then name your hosts: `tools/check-hosts <host>...`, or `CHECK_HOSTS`. The
host the command runs on (by `hostname -s`) runs `make check
check-opt2` in the tree itself; every other one gets a copy. Without
other machines, `make check` (and `make check-opt2`) on your own is the
check, and says nothing about the other systems.

## 5. Making a change visible

A change a user can see is described where a user looks: the User's
Guide (`doc/users-guide.md`, how to use poc), the Reference Guide
(`doc/reference-guide.md`, exactly what poc accepts and does), `poc(1)`
(`doc/poc.1`, every option), and for a language extension
`doc/developer/language-extensions.md` with its summary in `AGENTS.md`.
`doc/developer/llvm-toolchain.md` records how poc drives clang.

## 6. Building the packages

Each package is built on a host running its system and architecture -
the original developer's are section 4's: alerik and rackhir for FreeBSD
amd64 and arm64, cymoril and jherek for OpenBSD i386 and amd64, artos and
yishana for NetBSD amd64 and i386, atla for Fedora. The paths below (`$HOME/ports-work`,
`~/pkgsrc-work`) are theirs; any will do. Each package is built from a
release tarball (`make dist`, section 7),
named in it by version and fetched from the GitHub release; until there is
one, copy the tarball to where the system looks for it, as below. A
tarball already there is used as it is, not fetched again: once the
release is published, move any earlier one of the same name aside (`mv`
it to `.prerelease`), so that `makesum` fetches the published one and
records its sums. Each is then built, installed, checked against the
installed poc with `test/install/check.sh <installed poc> <scratch dir>`,
and removed, and nothing may be left. Installing and removing need root;
the rest does not. FreeBSD's and pkgsrc's `lang/peaseblossom-vax` depend on
`peaseblossom` of the same version, and neither will stage or package
until it is installed (FreeBSD's looks for its origin in `/usr/ports`,
pkgsrc's tries to become root to install it): build `lang/peaseblossom`
first, install its package, then build `lang/peaseblossom-vax`.

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

The steps are those the original developer follows on their machines
(section 4): atla for the tarball, the RPM and the signing, and the BSD
hosts for their packages. With other machines, the steps are the same;
the names, and the variables that give them to the tools, are yours.

1. **The version.** `make set-version VERSION=<x.y.z>` (`tools/set-version`)
   sets `number` in `src/driver/Version.Mod`, and the same version in each
   package: `Version` in the spec (with `Release` back to 1),
   `DISTVERSION` in the FreeBSD ports, `V` in the OpenBSD port and
   `DISTNAME` in pkgsrc's packages (`peaseblossom-vax` is a port of its
   own for FreeBSD and pkgsrc, a subpackage for Fedora and OpenBSD), and in `INSTALL.md`'s example, the
   Reference Guide's "describes poc <major.minor>" and the VAX/VMS
   Guide's example of unpacking the kits. It removes any
   `PORTREVISION`, `REVISION` or `PKGREVISION`, and adds a `%changelog` entry that says only "Update to
   <x.y.z>.", for you to fill in. A library records the version that
   built it, and poc refuses one from another version, so libraries are
   rebuilt.
2. **Check** on the four hosts (section 4), with `check-install` and
   `check-seed` as well:

       tools/check-hosts -t check-install -t check-seed

3. **Commit and push**, then check that commit on rackhir:
   `tools/check-hosts -c HEAD rackhir`. Check the kits of poc for VAX/VMS
   on the guest too (section 4, "The VAX/VMS development system"), from
   that commit: `make check-vax-kit` (with `CHECK_VAX_KIT_FLAGS=-full`
   when poc's own source changed for the VAX).
4. **The tarball**, from that commit, on atla (any machine with
   `make doc`'s tools, section 2):

       make stage2               # the seed is written by a Stage 2 built from HEAD
       make distcheck            # make dist (build/dist/peaseblossom-<version>.tar.gz
                                 # and .sha256), then builds it without voc and
                                 # runs check-install and check-install-vax
       make dist-sign            # .asc, with gpg's default key (GPG_KEY=... for another)

   `make dist` refuses a tree that differs from HEAD, or a Stage 2 built
   from another commit. It also writes the kits of poc for VAX/VMS,
   `build/dist/POC-<version>.COM` and `POC-VMS-<version>.COM` (the
   version's periods made hyphens; `tools/bootstrap/make-vax-kit`,
   `vax-macro32-backend.md` section 21), and puts copies in the tarball as
   `vax/`. It runs `make doc` (section 2), and puts the HTML
   and PDF documents in the tarball, as `doc/html` and `doc/pdf`, and the
   VAX/VMS Guide as text, as `doc/text`, so that a package needs no
   document tools: `install-vax` takes the kits and the guide from there. Each `make dist` writes a new tarball (tar and
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

6. **Publish** the tarball with its `.sha256` and `.asc`, and the VAX/VMS
   kits:

       gh release create v0.1.0 build/dist/peaseblossom-0.1.0.tar.gz{,.sha256,.asc} \
         build/dist/POC-0-1-0.COM build/dist/POC-VMS-0-1-0.COM --title "Peaseblossom 0.1.0" --notes-file <notes>

   and on the project's own site. Besides what changed, the notes say how
   to install each package (`INSTALL.md`, section 5, "Installing a
   release's package"), with this release's file names: as root,
   `dnf install ./<rpm>`, `pkg add ./<pkg>` or `pkg_add ./<tgz>`; and for
   OpenBSD, whose `pkg_add` takes a package only under its own name,
   `peaseblossom-<version>.tgz`, the download under that name with
   `ftp -o` and `pkg_add -D unsigned`. `peaseblossom-vax`, for `poc
   -target vax-dec-vms`, installs the same way, after `peaseblossom`. For
   VAX/VMS itself they point to the VAX/VMS Guide, chapter 1: the kits
   copied in ASCII mode, the STARLET kit unpacked over the base kit,
   `@BUILD`, `@SETUP`.
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
       peaseblossom-vax-<version>-1.fc44.noarch.rpm
       peaseblossom-<version>-freebsd15.1-amd64.pkg, peaseblossom-<version>-freebsd15.1-arm64.pkg
       peaseblossom-vax-<version>-freebsd15.1.pkg
       peaseblossom-<version>-openbsd7.9-i386.tgz, peaseblossom-<version>-openbsd7.9-amd64.tgz
       peaseblossom-vax-<version>-openbsd7.9.tgz
       peaseblossom-<version>-netbsd11.0-amd64.tgz, peaseblossom-<version>-netbsd11.0-i386.tgz
       peaseblossom-vax-<version>-netbsd11.0-amd64.tgz, peaseblossom-vax-<version>-netbsd11.0-i386.tgz
       SHA256SUMS, SHA256SUMS.asc   # sha256sum of every file; gpg --armor --detach-sign

   `peaseblossom-vax` is all text: one package for FreeBSD (`NO_ARCH`)
   and for OpenBSD (`PKG_ARCH = *`), but one for each NetBSD
   architecture, since pkgsrc's packages are each for a machine. It is
   built as `peaseblossom` is: Fedora's and OpenBSD's from the same spec
   or port, FreeBSD's and pkgsrc's from `lang/peaseblossom-vax`, which
   shares `lang/peaseblossom`'s `distinfo` and builds poc from the seed
   again. OpenBSD's and pkgsrc's packing lists (`PLIST-vax`, `PLIST`)
   name the kits by `${KIT_V}`, the version with hyphens.

   `make release-files` (`tools/release-files`) gathers them in
   `build/release/<version>/`:
   - the tarball's three files, and the VAX/VMS kit, from `build/dist`;
   - the RPMs from `~/rpmbuild` (`RPM_DIR`);
   - each BSD package by `scp` from the host that built it, named for that
     host's `uname`. `FREEBSD_HOSTS`, `OPENBSD_HOSTS` and `NETBSD_HOSTS`
     name those hosts, one for each architecture; they default to the
     original developer's, `"alerik rackhir"`, `"cymoril jherek"` and
     `"artos yishana"`.

   It refuses to go on until the RPMs there are signed. Sign them in place
   with the `rpmsign` command it prints, then run it again; a file already
   in the directory is kept. It then writes `SHA256SUMS` and signs it
   (`GPG_KEY` as for `dist-sign`). It uploads nothing, but prints the
   command that does:

       gh release upload v<version> --clobber build/release/<version>/*

   Each binary package is for that one system release and architecture;
   on any other, poc is built from the tarball or from `packaging/`.
8. **Install the kits on the VAX/VMS development system** (section 4),
   in `DUA1:[POC]`, owned by `POC`: there the guest's other users get
   the release's poc with `@DUA1:[POC]SETUP`, for work other than on poc
   itself. Install them as the VAX/VMS Guide's chapter 1 says, with
   the published kits (`build/dist`'s, the same bytes): unpack the base
   kit and then the STARLET kit in `DUA1:[POC]`, `@BUILD`, and give the
   tree world read and execute access, which `POC`'s default protection
   does not:

       $ SET FILE/PROTECTION=(S:RWED,O:RWED,G:RE,W:RE) DUA1:[POC...]*.*;*

   `tools/vax-do` with `VAX_USER=poc` does it from atla: the kits are its
   input files, and its procedure does `SET DEFAULT DUA1:[POC]` and runs
   them from `POC`'s home (`@'HOME'POC-<version>`). It takes a few
   minutes (0.10.1: unpacking and `@BUILD` about 6). A kit refuses a
   directory that holds an installation, so the previous release's tree
   is deleted first. Then check it as another user, `POC2`: `@DUA1:[POC]SETUP`,
   `POC -VERSION`, and the guide's chapter 2, `HELLO.MOD` built and run.
