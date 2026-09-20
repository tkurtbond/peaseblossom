# Peaseblossom - poc (Peaseblossom Oberon Compiler)

This is a project to develop an Oberon-2 compiler.

There are two desired outcomes: a compiler with a LLVM based backend that can be used on 32- and 64-bit computers, and another bespoke backend that will run on VAX/VMS 5.5-2.

The LLVM-based compiler should run on Linux as well as NetBSD, OpenBSD, and FreeBSD.

## Building and testing

Requires GNU Make and `voc` (Vishap Oberon, the bootstrap compiler - see
`AGENTS.md`) on `PATH`, or `VOC_BIN_DIR` set to its `bin` directory.

```
make            # builds poc into build/bin/poc (the default target)
make test       # runs the full conformance suite (test/conformance/)
make test-lexer # runs just one part of it - see GNUmakefile for the
                 # full list (test-parser, test-semantic, test-modules,
                 # test-layout, test-llvm, test-misc)
make stage1     # poc built by poc (build/stage1/bin/poc): the voc-built
                 # poc compiles poc's own source
make test-stage1 # the full suite under that poc-built poc
make stage2     # poc builds itself again with Stage 1's, and the two
                 # builds' output is compared (the self-hosting fixed point)
make check      # both compilers and the fixed point: make test,
                 # make test-stage1 and make stage2, reporting every failure
make clean      # removes both poc's own build output and test artifacts
                 # (clean-build and clean-tests individually)
```

`make test` runs the suite under the voc-built poc only: it is the fast loop,
and voc stays the bootstrap root and the comparison oracle. Use `make check`
before a commit that touches the compiler or the runtime (`rtl/llvm`).
