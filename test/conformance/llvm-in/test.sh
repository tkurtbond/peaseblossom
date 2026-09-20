#!/bin/sh
. ../../testenv.sh
# intest uses only what poc's In shares with voc's, so both compilers must
# print the same thing when fed the same input (llvm-in-extra has the
# rest). voc runs first and its symbol files go before poc starts: poc
# leaves In.sym and Out.sym in the working directory, which voc would find
# and reject as not its own.
voc intest.mod -m >/dev/null
./intest <input.txt >voc-output
rm -f *.c *.h *.o *.sym intest

# In, Out and Console are rtl modules: poc finds them through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc -o llvm-in -build intest.mod >result
./llvm-in <input.txt >poc-output
cat poc-output >>result
cmp -s poc-output voc-output || echo "poc and voc disagree on intest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
