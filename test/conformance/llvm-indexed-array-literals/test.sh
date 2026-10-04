#!/bin/sh
. ../../testenv.sh
# Phase 14: indexed array elements ([48..57]: 1) in literals and structured
# constants, local and imported, under both size models; then the interface
# Tables.sym gives.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  for program in indexed usetables
  do
    printf '== %s %s\n' "$model" "$program" >>result
    poc $model -o "$exe" -build $program.mod >>result 2>&1
    "./$exe" >>result 2>&1
  done
done
cat Tables.sym >>result
. ../../testresult.sh
