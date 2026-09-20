#!/bin/sh
. ../../testenv.sh
# bytestest uses only what poc's SYSTEM shares with voc's, on cases voc defines, so
# both compilers must print the same thing (llvm-system-extra has the rest).
# voc runs first and its symbol files go before poc starts: poc leaves
# .sym files in the working directory, which voc would find and reject as
# not its own.
voc bytestest.mod -m >/dev/null
./bytestest >voc-output
rm -f *.c *.h *.o *.sym bytestest

# Out and Console are rtl modules: poc finds them through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run bytestest.mod
tail -n +2 result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on bytestest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
