#!/bin/sh
# '.' this file from individual test.sh scripts, before running any compiler.
#
# Puts both the bootstrap compiler (voc) and poc's own build (once built by
# tools/bootstrap/stage0) on PATH, and cleans generated build artifacts left
# by a previous run. See PLAN.md, "Bootstrap terminology".
#
# A BACKEND-selection variant of this file existed briefly in Phase 0, in
# anticipation of PLAN.md Phase 8's LLVM/VAX backend split - removed as
# premature (poc had no backend at all until Phase 8). PLAN.md Phase 8
# step 3 revisited this once the LLVM backend actually existed and found
# a BACKEND variable still isn't needed: every fixture already names
# whichever compiler it wants directly (voc or poc), and that hasn't
# changed now that poc has its own LLVM backend - see llvm-build-run for
# a fixture that calls poc directly, same as every voc-based fixture
# calls voc directly. What step 3 actually needed was a shared helper for
# the one new repeated pattern LLVM fixtures introduce - see
# poc_build_run below - not a backend-selection mechanism.

: "${VOC_BIN_DIR:=/usr/local/sw/versions/voc/git/bin}"
: "${POC_BIN_DIR:=$PWD/../../../build/bin}"

echo "--- conformance test $(basename "$PWD") ---"

export PATH="$POC_BIN_DIR:$VOC_BIN_DIR:$PATH"


# *.c/*.h (voc's own C intermediates) were missing from this list until
# GNUmakefile's clean-tests target (which reuses this exact line via a
# standalone `. testenv.sh`, not by duplicating it) surfaced real,
# already-gitignored leftovers this never actually removed.
rm -f *.o *.c *.h *.ll *.s *.mar *.sym result "$(basename "$PWD")"

# PLAN.md Phase 8 step 3: compiles $1 (an Oberon-2 source file) via poc's
# LLVM backend into an executable named after this fixture's own
# directory (so the cleanup line above already removes a stale one from a
# previous run - the same "$(basename "$PWD")" convention test/conformance/
# hello already established for voc's own -m build), then runs it,
# appending both poc's own message and the program's stdout to "result".
# Centralizes the "poc -o <exe> -build <file>, then run <exe>" pattern so future
# fixtures promoted to compile+link+run+diff (PLAN.md's "Testing summary"
# for Phase 8) don't each hand-roll the exact clang-backed CLI incantation.
poc_build_run() {
  exe=$(basename "$PWD")
  poc -o "$exe" -build "$1" >result
  "./$exe" >>result
}
