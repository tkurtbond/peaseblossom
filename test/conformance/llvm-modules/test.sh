#!/bin/sh
. ../../testenv.sh
# modulestest uses only what poc's Modules shares with voc's, so both
# compilers must print the same thing (llvm-modules-extra has the rest).
# voc runs first and its symbol files go before poc starts: poc leaves
# Modules.sym and Console.sym in the working directory, which voc would
# find and reject as not its own.
voc modulestest.mod -m >/dev/null
./modulestest alpha "two words" "" 42 -7 >voc-output
rm -f *.c *.h *.o *.sym modulestest

# Modules and Console are rtl modules: poc finds them through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc -o llvm-modules -build modulestest.mod >result 2>&1
./llvm-modules alpha "two words" "" 42 -7 >poc-output
cat poc-output >>result
cmp -s poc-output voc-output || echo "poc and voc disagree on modulestest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
