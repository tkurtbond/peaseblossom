#!/bin/sh
. ../../testenv.sh
# consoletest uses only what poc's Console shares with voc's, so both
# compilers must print the same thing (llvm-console-extra has the rest).
# voc runs first and its symbol files go before poc starts: poc leaves
# Console.sym in the working directory, which voc would find and reject
# as not its own.
voc consoletest.mod -m >/dev/null
./consoletest >voc-output
rm -f *.c *.h *.o *.sym consoletest

# Console is an rtl module: poc finds it through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run consoletest.mod
tail -n +2 result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on consoletest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
