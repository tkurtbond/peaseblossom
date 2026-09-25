#!/bin/sh
. ../../testenv.sh
# The same program under both size models; each run's output is the expected
# text (voc's, checked by hand 2026-09-25).
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  printf '== %s\n' "$model" >>result
  poc $model -o "$exe" -build largerecords.mod | grep -v '^semantic OK' >>result
  "./$exe" >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
. ../../testresult.sh
