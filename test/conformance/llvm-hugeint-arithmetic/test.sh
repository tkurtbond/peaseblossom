#!/bin/sh
. ../../testenv.sh
# HUGEINT arithmetic at run time (Phase 11 C3): on a 32-bit target every
# operation is a pair of 32-bit words, so carries, borrows, 64-bit multiply
# and DIV/MOD go through code a 64-bit build never exercises. voc prints the
# same under both size models; its output is the reference, and poc must match
# it under -O2 and -OC. llvm-i686-runtime runs the -O2 build as a real 32-bit
# executable; this fixture also runs the -OC one there, where LONGINT is 64
# bits too. voc runs first and its files go before poc starts: poc leaves .sym
# files in the working directory, which voc would reject as not its own.
voc -m hugeint.mod >/dev/null
./hugeint >voc-o2
rm -f *.c *.h *.o *.sym hugeint
voc -OC -m hugeint.mod >/dev/null
./hugeint >voc-oc
rm -f *.c *.h *.o *.sym hugeint

POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run hugeint.mod
tail -n +2 result >poc-o2
cmp -s poc-o2 voc-o2 || echo "poc and voc disagree under -O2" >>result
poc -OC -o "$exe" -build hugeint.mod >/dev/null
"./$exe" >poc-oc
cmp -s poc-oc voc-oc || echo "poc and voc disagree under -OC" >>result
if i686_can_run
then
  poc -OC -target "$(i686_triple)" -o "$exe" -build hugeint.mod >/dev/null
  "./$exe" >poc-oc-i686
  cmp -s poc-oc-i686 voc-oc || echo "poc -OC on i686 and voc disagree" >>result
fi
rm -f voc-o2 voc-oc poc-o2 poc-oc poc-oc-i686
. ../../testresult.sh
