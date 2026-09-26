#!/bin/sh
. ../../testenv.sh
# NEW needs the runtime (the collector) on the import path. Built under -O2
# and -OC: the output must not depend on the size model.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run nesteduplevel.mod
poc -OC -o "$(basename "$PWD")" -build nesteduplevel.mod >result.OC 2>&1
"./$(basename "$PWD")" >>result.OC
cmp -s result result.OC || echo "-OC output differs" >>result
rm -f result.OC
. ../../testresult.sh
