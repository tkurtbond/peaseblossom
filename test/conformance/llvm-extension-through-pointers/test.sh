#!/bin/sh
. ../../testenv.sh
# NEW allocates through the runtime's collector, found through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run lsb.mod
. ../../testresult.sh
