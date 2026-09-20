#!/bin/sh
. ../../testenv.sh
# Strings where poc's differs from voc's (truncation, arrays with no 0X,
# exactly rounded numbers), so poc only; llvm-strings has the rest.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run stringsextra.mod
. ../../testresult.sh
