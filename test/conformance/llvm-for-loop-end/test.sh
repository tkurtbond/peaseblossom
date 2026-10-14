#!/bin/sh
. ../../testenv.sh
# FOR's end (AGENTS.md, "FOR final value"): each line is the number of
# iterations and the control variable's value after the loop. The same
# output under both size models.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build forend.mod >result 2>&1
"./$exe" >>result
poc -OC -o "$exe" -build forend.mod >result.oc 2>&1
"./$exe" >>result.oc
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
