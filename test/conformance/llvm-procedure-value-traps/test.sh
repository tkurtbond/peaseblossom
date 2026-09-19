#!/bin/sh
. ../../testenv.sh
# Like llvm-pointer-traps: each program's stdout and stderr (the trap's own
# message) and exit status go into "result". Every program prints "A", then
# must trap before it can print "B".
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for name in nilglobal nillocal nilfield nilelement nilproper nilargument nilpointer
do
  echo "== $name" >>result
  poc -o "$name.exe" -build "$name.mod" >/dev/null
  "./$name.exe" >>result 2>&1
  printf '\nexit=%d\n' "$?" >>result
done
. ../../testresult.sh
