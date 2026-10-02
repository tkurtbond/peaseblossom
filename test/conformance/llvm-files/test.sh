#!/bin/sh
. ../../testenv.sh
# filestest uses only what poc's Files shares with voc's, so both compilers
# must print the same thing (llvm-files-extra has the rest). voc runs first
# and its symbol files go before poc starts: poc leaves Files.sym and the
# others in the working directory, which voc would find and reject as not
# its own.
voc filestest.mod -m >/dev/null
./filestest >voc-output
rm -f *.c *.h *.o *.sym filestest

# Files, Platform and Console are rtl modules: poc finds them through the
# import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run filestest.mod
cat result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on filestest" >>result
rm -rf poc-output voc-output work
. ../../testresult.sh
