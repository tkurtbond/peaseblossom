#!/bin/sh
. ../../testenv.sh
# shiftstest uses only what poc's SYSTEM shares with voc's, on cases voc defines, so
# both compilers must print the same thing (llvm-system-extra has the rest).
# voc runs first and its symbol files go before poc starts: poc leaves
# .sym files in the working directory, which voc would find and reject as
# not its own.
voc shiftstest.mod -m >/dev/null
./shiftstest >voc-output
rm -f *.c *.h *.o *.sym shiftstest

# Out and Console are rtl modules: poc finds them through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run shiftstest.mod
tail -n +2 result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on shiftstest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
