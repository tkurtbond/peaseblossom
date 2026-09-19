#!/bin/sh
. ../../testenv.sh
# NEW allocates through the runtime's collector, which poc adds to the
# program itself (poc: AddRuntimeModules) but finds through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run gcnew.mod
. ../../testresult.sh
