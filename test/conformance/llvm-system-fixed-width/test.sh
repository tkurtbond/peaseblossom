#!/bin/sh
. ../../testenv.sh
# The same program under both size models: only the LONGINT line may differ.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build fixed.mod >build.out 2>&1
  grep -v '^semantic OK' build.out >>result
  "./$exe" >>result
done
rm -f build.out
. ../../testresult.sh
