#!/bin/sh
. ../../testenv.sh
# Out.LongReal/Out.Real against the C library's printf, see generate.py.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build digits.mod >build.out
grep -v '^semantic OK' build.out
"./$exe" | sed 's/^ *//' >result
rm -f build.out
. ../../testresult.sh
