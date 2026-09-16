#!/bin/sh
# '.' this file from individual test.sh scripts, before running any compiler.
#
# Puts both the bootstrap compiler (voc) and poc's own build (once built by
# tools/bootstrap/stage0) on PATH, and cleans generated build artifacts left
# by a previous run. See PLAN.md, "Bootstrap terminology".
#
# A BACKEND-selection variant of this file existed briefly in Phase 0, in
# anticipation of PLAN.md Phase 8's LLVM/VAX backend split - that concern
# doesn't exist yet (poc has no backend at all until Phase 8), so it was
# premature and has been removed; reintroduce it when Phase 8 actually
# needs to select between codegen targets.

: "${VOC_BIN_DIR:=/usr/local/sw/versions/voc/git/bin}"
: "${POC_BIN_DIR:=$PWD/../../../build/bin}"

echo "--- conformance test $(basename "$PWD") ---"

export PATH="$POC_BIN_DIR:$VOC_BIN_DIR:$PATH"

rm -f *.o *.ll *.s *.mar *.sym result "$(basename "$PWD")"
