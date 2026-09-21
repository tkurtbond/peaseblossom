#!/bin/sh
. ../../testenv.sh
# The same program under both size models; every line must be the same.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build longshort.mod >build.out
  grep -v '^semantic OK' build.out >>result
  "./$exe" >>result
done
rm -f build.out
. ../../testresult.sh
