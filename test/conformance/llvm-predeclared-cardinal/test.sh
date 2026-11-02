#!/bin/sh
. ../../testenv.sh
# The predeclared unsigned types in a program that imports no SYSTEM, under
# both size models (doc/developer/language-extensions.md, "Predeclared
# unsigned types").
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "$model:" >>result
  poc $model -o "$exe" -build cardinal.mod >>result 2>&1
  "./$exe" >>result 2>&1
  echo "exit $?" >>result
done
. ../../testresult.sh
