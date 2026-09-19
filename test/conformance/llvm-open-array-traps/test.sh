#!/bin/sh
. ../../testenv.sh
# Like llvm-pointer-traps: each program's stdout and stderr (the trap's own
# message) and exit status go into "result". Every program prints "A", then
# must trap before it can print "B" - except toobig, where NEW of more than
# the heap can supply answers NIL (it does not trap, as for a record) and
# the program says so, then goes on.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for name in paramindex paramnegative pointerindex matrixindex nilelement nillength zerolength negativelength zeroinner overflow toobig
do
  echo "== $name" >>result
  poc -o "$name.exe" -build "$name.mod" >/dev/null
  "./$name.exe" >>result 2>&1
  printf '\nexit=%d\n' "$?" >>result
done
. ../../testresult.sh
