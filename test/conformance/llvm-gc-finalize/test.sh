#!/bin/sh
. ../../testenv.sh
# finalize.mod: the collector's side. Then one program for each way a
# program ends, each with two objects registered: stdout and stderr (a
# trap's message) and the exit status go into "result".
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run finalize.mod
for name in atend halt assertfail indextrap niltrap platformexit
do
  echo "== $name" >>result
  poc -o "$name.exe" -build "$name.mod" >/dev/null
  "./$name.exe" >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
rm -f *.sym
. ../../testresult.sh
