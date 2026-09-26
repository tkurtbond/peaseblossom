#!/bin/sh
. ../../testenv.sh
# SYSTEM.SET64 and the 32-bit SET, under both size models: the same output,
# since a SET is 32 bits and a SET64 64 whichever model is chosen.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build set64.mod >result 2>&1
"./$exe" >>result
poc -OC -o "$exe" -build set64.mod >result.oc 2>&1
"./$exe" >>result.oc
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
