#!/bin/sh
. ../../testenv.sh
# The predeclared unsigned types across a module boundary, through the .sym
# file (doc/developer/language-extensions.md, "Predeclared unsigned types"):
# constants, MAX(HUGECARD) as a pattern, a type, its fields, a procedure type,
# a variable and a procedure, under both size models, with SYSTEM imported by
# one module only, and the interface as the .sym file writes it. ModelLib also
# has a constant of a SYSTEM.CARD16 that it names only through WidthTypes.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build ModelUse.mod ModelLib.mod WidthTypes.mod 2>&1 | grep -v '^semantic OK' >>result
  "./$exe" >>result
  echo "== ModelLib.sym" >>result
  cat ModelLib.sym >>result
done
. ../../testresult.sh
