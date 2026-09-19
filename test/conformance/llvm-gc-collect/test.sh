#!/bin/sh
. ../../testenv.sh
# the runtime modules live in rtl/llvm, found through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run gc.mod
. ../../testresult.sh
