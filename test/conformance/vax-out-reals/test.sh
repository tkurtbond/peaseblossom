#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.7, proposals 2, 3 and 6): Out's and Err's Real, LongReal, Ten and
# IsConsole on VAX/VMS, with the LLVM fixtures' programs: llvm-out-extra's
# outextra.mod, llvm-err's errtest.mod, and llvm-out's outtest.mod without
# the lines that make an infinity and a NaN by multiplying past the range,
# which fault on the VAX. For -O2 and -OC, each built for the VAX and run
# there (vax_do, guest-run.com), errtest with SYS$OUTPUT and SYS$ERROR sent
# to two files, as llvm-err runs it with the streams apart; together they
# must print guest-run-O2.expected or guest-run-OC.expected, which differ
# where outtest prints MAX(INTEGER), MIN(INTEGER) and MAX(LONGINT).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="outextra.mar errtest.mar outtest.mar Out.mar Err.mar Console.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
cp ../llvm-out-extra/outextra.mod ../llvm-err/errtest.mod .
sed -e '/infinity and not a number/,/Out.LongReal(y, 0); Out.Ln;/d' ../llvm-out/outtest.mod >outtest.mod
rm -f outextra.com errtest.com outtest.com
: >result
for model in -O2 -OC; do
  rm -f *.sym $written
  for program in outextra errtest outtest; do
    poc $model -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1
    echo "VAX build $program $model exit $?" >>result
  done
  vax_do guest-run.com guest-run$model.expected outextra.com errtest.com outtest.com $written $rtl/PocRtl.mar
done
rm -f *.sym $written outextra.com errtest.com outtest.com outextra.mod errtest.mod outtest.mod
. ../../testresult.sh
