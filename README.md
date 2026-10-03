# Peaseblossom - poc (Peaseblossom Oberon Compiler)

This software is developed with the aid of AI.

This is a project to develop an Oberon-2 compiler.

There are two desired outcomes: a compiler with a LLVM based backend that can be used on 32- and 64-bit computers, and another bespoke backend that will run on VAX/VMS 5.5-2.

The LLVM-based compiler should run on Linux as well as NetBSD, OpenBSD, and FreeBSD.

## Building and testing

Requires GNU Make and `voc` (Vishap Oberon, the bootstrap compiler - see
`AGENTS.md`) on `PATH`, or `VOC_BIN_DIR` set to its `bin` directory. Without
voc, `make BOOTSTRAP_POC=<a poc>` builds with a poc already installed, and a
release tarball's `seed/` lets clang alone build it. The
LLVM backend's fixtures, `make stage1` and `make stage2` also need `clang`
on `PATH`: poc hands it the `.ll` it writes.

```
make             # builds poc into build/bin/poc (the default target;
                 # make build and make all are the same)
make test        # runs the full conformance suite (test/conformance/)
make test-lexer  # runs just one part of it - see GNUmakefile for the
                 # full list (test-parser, test-semantic, test-modules,
                 # test-layout, test-llvm, test-misc)
make stage1      # poc built by poc (build/stage1/bin/poc): the voc-built
                 # poc compiles poc's own source
make test-stage1 # the full suite under that poc-built poc
make stage2      # poc builds itself again with Stage 1's, and the two
                 # builds' output is compared (the self-hosting fixed point)
make check       # both compilers and the fixed point: make test,
                 # make test-stage1, make stage2 and make check-strict,
                 # reporting every failure
make check-strict # poc -strict on every module of src/: poc's own source
                 # uses only Oberon2.pdf
make install     # installs the Stage 2 poc and poc-rtl (PREFIX, default
                 # /usr/local; DESTDIR, BINDIR, LIBDIR, MANDIR, DOCDIR);
                 # make uninstall removes them
make check-install # installs into a scratch DESTDIR and builds and runs
                 # programs with only the installed poc and clang
make seed        # the bootstrap seed, poc's own IR (seed/), from which
                 # clang alone builds poc where there is no voc
make check-seed  # poc built from the seed builds the same Stage 1 as
                 # poc built by voc
make dist        # the release tarball, build/dist/peaseblossom-<version>
                 # .tar.gz: HEAD's source and the seed
make distcheck   # builds the tarball without voc and runs check-install
make dist-sign   # a GPG signature of the tarball (.asc), when wanted
make clean       # removes both poc's own build output and test artifacts
                 # (clean-build and clean-tests individually)
```

`poc` exits with status 1 after reporting an error of any kind (a type error, a
file that will not open, a failed build, a construct the LLVM backend cannot
lower yet) and 0 otherwise.

`make test` runs the suite under the voc-built poc only: it is the fast loop,
and voc stays the bootstrap root and the comparison oracle. Use `make check`
before a commit that touches the compiler or the runtime (`rtl/llvm`).
