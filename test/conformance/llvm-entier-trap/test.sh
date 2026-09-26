#!/bin/sh
. ../../testenv.sh
# One program, one case per run (its argument), under both size models: the
# output and exit status of each run are the expected text.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  poc $model -o "$exe" -build entiertrap.mod 2>&1 | grep -v '^semantic OK' >>result
  for case in 0 1 2 3 4 5 6 7 8 9
  do
    printf '== %s case %s\n' "$model" "$case" >>result
    "./$exe" "$case" >>result 2>&1
    printf '\nexit=%d\n' "$?" >>result
  done
done
. ../../testresult.sh
