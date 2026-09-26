#!/bin/sh
. ../../testenv.sh
# More than 8 open dimensions (Phase 11 A17): nine and twenty, through
# parameters, LEN, NEW, rows and a nested procedure (see manydims.mod).
# poc's output is expected; voc's must match it under both size models up
# to the "nested" lines at the end: voc gives a nested procedure garbage
# inner lengths for an open array of two or more dimensions, and stops
# with nine (doc/voc-bugs/README.md), before its buffered "nested " is out. voc runs first and its
# files go before poc starts: poc leaves .sym files voc would reject.
voc -m manydims.mod >/dev/null
./manydims 2>&1 | sed -e '/^nested/,$d' -e '/^Terminated by Halt/,$d' >voc-o2
rm -f *.c *.h *.o *.sym manydims
voc -OC -m manydims.mod >/dev/null
./manydims 2>&1 | sed -e '/^nested/,$d' -e '/^Terminated by Halt/,$d' >voc-oc
rm -f *.c *.h *.o *.sym manydims

POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run manydims.mod
tail -n +2 result | sed '/^nested/,$d' >poc-o2
cmp -s poc-o2 voc-o2 || echo "poc and voc disagree under -O2" >>result
poc -OC -o "$exe" -build manydims.mod >/dev/null 2>&1
"./$exe" | sed '/^nested/,$d' >poc-oc
cmp -s poc-oc voc-oc || echo "poc and voc disagree under -OC" >>result
rm -f voc-o2 voc-oc poc-o2 poc-oc
. ../../testresult.sh
