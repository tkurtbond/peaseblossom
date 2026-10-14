#!/bin/sh
. ../../testenv.sh
# The unsigned types (AGENTS.md, "Unsigned integer types") under both size
# models: the same output, since each has the same width under both.
# Standard error, Err's line, is part of the output.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build cardinal.mod >result 2>&1
"./$exe" >>result 2>&1
poc -OC -o "$exe" -build cardinal.mod >result.oc 2>&1
"./$exe" >>result.oc 2>&1
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
