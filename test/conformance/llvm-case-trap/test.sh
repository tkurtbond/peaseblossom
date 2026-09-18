#!/bin/sh
. ../../testenv.sh
# See llvm-index-range-trap/test.sh's own comment for why this doesn't
# reuse poc_build_run.
exe=$(basename "$PWD")
poc -o "$exe" -build casetrap.mod >result
"./$exe" >>result 2>&1
printf '\nexit=%d\n' "$?" >>result
. ../../testresult.sh
