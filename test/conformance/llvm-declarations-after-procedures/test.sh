#!/bin/sh
. ../../testenv.sh
# client.mod imports Out from rtl/llvm and lib.mod from here; -build finds
# both, and builds under each size model.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "$model" >>result
  poc $model -o "$exe" -build client.mod >>result 2>&1
  "./$exe" >>result
done
. ../../testresult.sh
