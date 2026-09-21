#!/bin/sh
. ../../testenv.sh
# voc's array assignment (doc/array-assignment-survey.md): voc does the same,
# so voc's output under each size model is the reference and poc must print it
# too.  voc runs first and its files go before poc starts: poc leaves .sym
# files in the working directory, which voc would find and reject as not its
# own.
voc -m arrayassign.mod >/dev/null
./arrayassign >voc-o2
rm -f *.c *.h *.o *.sym arrayassign
voc -OC -m arrayassign.mod >/dev/null
./arrayassign >voc-oc
rm -f *.c *.h *.o *.sym arrayassign

POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
echo "-O2" >result
poc -o "$exe" -build arrayassign.mod >/dev/null
"./$exe" >poc-o2
cat poc-o2 >>result
echo "-OC" >>result
poc -OC -o "$exe" -build arrayassign.mod >/dev/null
"./$exe" >poc-oc
cat poc-oc >>result
cmp -s poc-o2 voc-o2 || echo "poc and voc disagree under -O2" >>result
cmp -s poc-oc voc-oc || echo "poc and voc disagree under -OC" >>result
rm -f poc-o2 poc-oc voc-o2 voc-oc
. ../../testresult.sh
