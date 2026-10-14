#!/bin/sh
. ../../testenv.sh
# The unsigned types across a module boundary, through the .sym file
# (AGENTS.md, "Unsigned integer types"): constants of a CARD type, one above
# MAX(HUGEINT), a variable, record fields and procedures. The same output
# under both size models, and the interface as the .sym file writes it.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build carduse.mod 2>&1 | grep -v '^semantic OK' >>result
  "./$exe" >>result
done
echo "== CardLib.sym" >>result
cat CardLib.sym >>result
. ../../testresult.sh
