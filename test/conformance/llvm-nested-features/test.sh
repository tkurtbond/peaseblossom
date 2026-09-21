#!/bin/sh
. ../../testenv.sh
# NEW needs the runtime (the collector) on the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run nestedfeatures.mod
. ../../testresult.sh
