#!/bin/sh
. ../../testenv.sh
# Args (rtl/llvm/Args.Mod), voc's v4 Args with Platform's getEnv: the same
# program built by voc and by poc must print the same, for arguments
# (including an empty one and numbers) and for a variable that is set, set
# empty and not set. voc runs first and its files go before poc starts.
unset ARGSTEST_UNSET
run() { ARGSTEST_SET=value ARGSTEST_EMPTY= "$@" alpha "" 42 -7 x9; }
voc argstest.mod -m >/dev/null
run ./argstest >voc-output
rm -f *.c *.h *.o *.sym argstest
unset POC_IMPORT_PATH POC_LIBRARY_PATH
poc -o llvm-args argstest.mod >result 2>&1
run ./llvm-args >poc-output
cat poc-output >>result
cmp -s poc-output voc-output || { echo "poc and voc disagree on argstest" >>result; diff voc-output poc-output >>result; }
rm -f poc-output voc-output llvm-args
. ../../testresult.sh
