#!/bin/sh
. ../../testenv.sh
# Doesn't reuse poc_build_run - this fixture needs the built program's
# own exit status (HALT's whole point), which poc_build_run's own
# ">result"/">>result" plumbing doesn't capture; see
# llvm-index-range-trap/test.sh for the same reasoning applied to a
# trap's own exit status instead of HALT's.
exe=$(basename "$PWD")
poc -o "$exe" -build predhalt.mod >result 2>&1
"./$exe" >>result
printf '\nexit=%d\n' "$?" >>result
. ../../testresult.sh
