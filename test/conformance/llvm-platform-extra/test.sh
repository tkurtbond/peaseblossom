#!/bin/sh
. ../../testenv.sh
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run platformextra.mod
. ../../testresult.sh
