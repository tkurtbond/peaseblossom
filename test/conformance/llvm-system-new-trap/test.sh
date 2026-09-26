#!/bin/sh
. ../../testenv.sh
# The program's exit status and stderr are part of the expected output (see
# llvm-index-range-trap's test.sh for why this does not use poc_build_run).
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build newtrap.mod >result 2>&1
"./$exe" >>result 2>&1
printf '\nexit=%d\n' "$?" >>result
. ../../testresult.sh
