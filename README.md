# Peaseblossom - poc (Peaseblossom Oberon Compiler)

This is a project to develop an Oberon-2 compiler.

There are two desired outcomes: a LLVM based compiler that can be used on 32- and 64-bit computers, and another compiler with a bespoke backend that will run on VAX/VMS 5.5-2.

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
make clean      # removes both poc's own build output and test artifacts
                 # (clean-build and clean-tests individually)
```
