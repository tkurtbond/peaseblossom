# Peaseblossom - poc (Peaseblossom Oberon Compiler)

This software is developed with the aid of AI.

This is a project to develop an Oberon-2 compiler.

There are two desired outcomes: a compiler with a LLVM based backend that can be used on 32- and 64-bit computers, and another bespoke backend that will run on VAX/VMS 5.5-2.

The LLVM-based compiler should run on Linux as well as NetBSD, OpenBSD, and FreeBSD.

## Installing

`INSTALL.md` is how to build and install poc: from a release tarball, which
needs only clang and GNU make, or from the git repository, and into
`/usr/local` or anywhere else. `packaging/` has packages for Fedora,
FreeBSD, OpenBSD and NetBSD (pkgsrc).

## Using poc

`doc/users-guide.md`, the User's Guide, is how to build programs and
libraries, read a trap, debug, call C and use the runtime modules; every
example in it is run by the test suite. `doc/reference-guide.md`, the
Reference Guide, says exactly what poc accepts and does, and `poc(1)`
(`doc/poc.1`) lists every option.

## Working on poc

`doc/developer/DEVELOPER.md` is how poc is built and tested while it is
being worked on, how a change is checked before it is committed, how the
packages are built and how a release is made. `PLAN.md` is the roadmap, and
`AGENTS.md` the project's standing decisions. `doc/README.md` lists every
document, grouped by who it is for.
