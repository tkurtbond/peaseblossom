#!/bin/sh
. ../../testenv.sh
# doc/developer/language-extensions.md, "External variables": what poc
# refuses. external-variable.mod: a local one, two identifiers with one
# linkage name, an unknown convention, traced pointers (directly and in a
# record's array), with SYSTEM.PTR, ADDRESS, a procedure type and a list
# without a name accepted. initializer.mod: an initializer (a parse error,
# so a file of its own). strict.mod: -strict. vmsonllvm.mod: "VMS" given
# to the LLVM backend.
unset POC_IMPORT_PATH
rm -rf work && mkdir work
: >result
for f in external-variable initializer; do
  echo "== $f.mod" >>result
  poc -check $f.mod >>result 2>&1
  echo "exit $?" >>result
done
echo "== strict.mod, -strict" >>result
poc -strict -check strict.mod >>result 2>&1
echo "exit $?" >>result
echo "== strict.mod" >>result
poc -check strict.mod >>result 2>&1
echo "exit $?" >>result
echo "== vmsonllvm.mod, LLVM" >>result
poc -output-dir work -emit-llvm-ir vmsonllvm.mod >>result 2>&1
echo "exit $?" >>result
rm -rf work
. ../../testresult.sh
