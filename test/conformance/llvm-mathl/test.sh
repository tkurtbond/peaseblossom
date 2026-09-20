#!/bin/sh
. ../../testenv.sh
# mathltest compares every function of the interface with the exact value
# to a relative tolerance, so both compilers' library must print the same
# (llvm-math-extra has what only poc's does). voc runs first and its symbol
# files go before poc starts: poc leaves .sym files in the working
# directory, which voc would find and reject as not its own.
voc mathltest.mod -m >/dev/null
./mathltest >voc-output
rm -f *.c *.h *.o *.sym mathltest

# Math, MathL, Out and Console are rtl modules: poc finds them through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run mathltest.mod
tail -n +2 result >poc-output
cmp -s poc-output voc-output || echo "poc and voc disagree on mathltest" >>result
rm -f poc-output voc-output
. ../../testresult.sh
