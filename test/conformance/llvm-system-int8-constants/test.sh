#!/bin/sh
. ../../testenv.sh
# The same program under both size models, built by poc and by voc: the two
# must print the same lines (the program keeps every INT8 in range, where voc's
# C arithmetic and poc's agree), and both models the same, since a constant
# next to an INT8 is an INT8 under -OC as under -O2.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for model in -O2 -OC
do
  # voc first: poc leaves Out.sym in the working directory, which voc would
  # find and reject as not its own
  voc $model int8const.mod -m >voc.out 2>&1 || { echo "voc $model failed" >>result; cat voc.out >>result; }
  ./int8const >voc-output
  rm -f *.c *.h *.o *.sym int8const voc.out
  poc $model -o llvm-system-int8-constants -build int8const.mod >build.out
  grep -v '^semantic OK' build.out >>result
  echo "== $model" >>result
  ./llvm-system-int8-constants >poc-output
  cat poc-output >>result
  cmp -s poc-output voc-output || echo "poc and voc disagree under $model" >>result
  rm -f poc-output voc-output build.out *.sym
done
. ../../testresult.sh
