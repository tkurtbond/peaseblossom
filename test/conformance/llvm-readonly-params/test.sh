#!/bin/sh
. ../../testenv.sh
# Read-only parameters (Phase 15's "Ongoing language enhancements" 1), under
# both size models: the same output.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build readonly.mod >result 2>&1
"./$exe" >>result
rm -f *.sym
poc -OC -o "$exe" -build readonly.mod >result.oc 2>&1
"./$exe" >>result.oc
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
