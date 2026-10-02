#!/bin/sh
. ../../testenv.sh
# commands.mod, then voc's run-time error stops: stdout and stderr and the
# exit status go into "result"
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for name in commands haltcode halt assertcode assertzero
do
  echo "== $name" >>result
  poc -o "$name.exe" -build "$name.mod" 2>&1 | grep -v '^semantic OK' >>result
  "./$name.exe" >>result 2>&1
  echo "exit=$?" >>result
done
rm -f *.sym
. ../../testresult.sh
