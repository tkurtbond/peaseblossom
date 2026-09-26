#!/bin/sh
. ../../testenv.sh
# Doesn't reuse testenv.sh's own poc_build_run: this fixture needs the
# built program's exit status and its stderr output (the trap's own
# diagnostic message, PLAN.md Phase 8 step 9), neither of which
# poc_build_run's ">result"/">>result" plumbing captures - every other
# LLVM runtime fixture only ever needs stdout. stderr is folded into
# the same "result" stream via "2>&1" rather than a second diff target:
# both write(2) targets are unbuffered raw syscalls in this single-
# threaded program, so their combined byte order is exactly execution
# order, not just "eventually consistent."
exe=$(basename "$PWD")
poc -o "$exe" -build idxtrap.mod >result 2>&1
"./$exe" >>result 2>&1
printf '\nexit=%d\n' "$?" >>result
. ../../testresult.sh
