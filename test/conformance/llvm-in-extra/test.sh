#!/bin/sh
. ../../testenv.sh
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc -o llvm-in-extra -build inextra.mod >result
./llvm-in-extra <input.txt >>result
. ../../testresult.sh
