#!/bin/sh
. ../../testenv.sh
# NEW is used (a type-bound procedure's receiver is a pointer), so poc adds
# the runtime's collector to the program, finding it through the import path.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run openparams.mod
. ../../testresult.sh
