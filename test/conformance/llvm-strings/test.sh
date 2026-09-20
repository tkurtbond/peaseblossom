#!/bin/sh
. ../../testenv.sh
# stringstest uses only what poc's Strings shares with voc's, on cases voc
# gets right, so both compilers must print the same thing
# (llvm-strings-extra has the rest). voc runs first and its symbol files go
# before poc starts: poc leaves Strings.sym and Out.sym in the working
# directory, which voc would find and reject as not its own.
voc stringstest.mod -m >/dev/null
./stringstest >voc-output
rm -f *.c *.h *.o *.sym stringstest

# Strings, Out and Console are rtl modules: poc finds them through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run stringstest.mod
tail -n +2 result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on stringstest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
