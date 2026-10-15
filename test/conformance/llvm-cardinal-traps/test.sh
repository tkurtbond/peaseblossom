#!/bin/sh
. ../../testenv.sh
# The run-time checks on the unsigned types (AGENTS.md, "Unsigned integer
# types"), as llvm-pointer-traps: each program prints "A", then must trap
# before it can print "B". The index checks are always on; SHORT and CHR
# are checked under -range-checks.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for name in bigindex openindex shortrange chrrange
do
  echo "== $name" >>result
  poc -range-checks -o "$name.exe" -build "$name.mod" >/dev/null
  "./$name.exe" >>result 2>&1
  printf '\nexit=%d\n' "$?" >>result
done
. ../../testresult.sh
