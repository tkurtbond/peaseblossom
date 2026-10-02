#!/bin/sh
. ../../testenv.sh
# platformtest uses only what poc's Platform shares with voc's, so both
# compilers must print the same thing (llvm-platform-extra has the rest).
# voc runs first and its symbol files go before poc starts: poc leaves
# Platform.sym in the working directory, which voc would find and reject
# as not its own.
rm -rf sub
mkdir sub
: >sub/marker
PLATFORM_TEST_VALUE="hello, world"
PLATFORM_TEST_EMPTY=""
export PLATFORM_TEST_VALUE PLATFORM_TEST_EMPTY

voc platformtest.mod -m >/dev/null
./platformtest >voc-output
rm -f *.c *.h *.o *.sym platformtest

# Platform is an rtl module: poc finds it, and Console, through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run platformtest.mod
cat result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on platformtest" >>result
rm -rf poc-output voc-output sub
. ../../testresult.sh
