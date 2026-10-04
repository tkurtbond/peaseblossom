#!/bin/sh
. ../../testenv.sh
# Phase 14: structured constants of an imported module, and literals of its
# types, under both size models; then the interface Shapes.sym gives.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  printf '== %s\n' "$model" >>result
  poc $model -o "$exe" -build client.mod >>result 2>&1
  "./$exe" >>result 2>&1
done
cat Shapes.sym >>result
. ../../testresult.sh
