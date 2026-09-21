#!/bin/sh
. ../../testenv.sh
# A SYSTEM.SET64 crossing a module boundary through the .sym file: an exported
# variable, record field, constant of that type and a procedure returning it,
# plus a hidden field of the record that an importer's layout still depends on.
# The same output under both size models.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build setuse.mod | grep -v '^semantic OK' >>result
  "./$exe" >>result
done
. ../../testresult.sh
