#!/bin/sh
. ../../testenv.sh
# OutStr (Phase 15's "Ongoing library enhancements" 1) under both size models:
# the same output, and in the first part each line Out wrote the same as the
# OutStr string after it (pairs of lines ending "|").
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build outstr.mod >result 2>&1
"./$exe" >>result
awk '/\|$/ { if (n % 2 == 0) first = $0; else if ($0 != first) print "differs: " first " / " $0; n++ }' result >differs
cat differs >>result; rm -f differs
poc -OC -o "$exe" -build outstr.mod >result.oc 2>&1
"./$exe" >>result.oc
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
