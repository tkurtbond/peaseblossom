#!/bin/sh
# '.' this file from individual test.sh scripts, before running the compiler.
#
# Selects and configures the compiler for the requested BACKEND
# (see PLAN.md, "Phase-to-report-section map" and "Bootstrap terminology"):
#
#   voc   - the bootstrap compiler (Vishap Oberon). Used for every test
#           until poc can compile and run its own LLVM backend (Phase 8+).
#   llvm  - poc's own LLVM backend, once it exists (Phase 8+).
#   vax   - poc's VAX/VMS backend. Codegen-only per PLAN.md Phase 10; no
#           assemble/link/run support exists, so tests are skipped.
#
# BACKEND defaults to voc, since that's the only backend that exists yet.

: "${BACKEND:=voc}"

echo "--- conformance test $(basename "$PWD") (backend: $BACKEND) ---"

case "$BACKEND" in
  voc)
    : "${VOC_BIN_DIR:=/usr/local/sw/versions/voc/git/bin}"
    export PATH="$VOC_BIN_DIR:$PATH"
    ;;
  llvm)
    : "${POC_BIN_DIR:=$PWD/../../../build/bin}"
    export PATH="$POC_BIN_DIR:$PATH"
    ;;
  vax)
    echo "SKIPPED: VAX/VMS backend has no runnable target yet (PLAN.md Phase 10)"
    exit 77
    ;;
  *)
    echo "unknown BACKEND: $BACKEND" >&2
    exit 1
    ;;
esac

rm -f *.o *.ll *.s *.mar *.sym result "$(basename "$PWD")"
