#!/bin/sh
. ../../testenv.sh
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc -o llvm-modules-extra -build modulesextra.mod >result
zeros=$(printf '%03000d' 0)
./llvm-modules-extra "$zeros" b >>result
. ../../testresult.sh
