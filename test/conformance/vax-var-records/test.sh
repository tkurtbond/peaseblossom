#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 5): VAR record parameters, which take their actual's type tag,
# and records holding pointers. poc -emit-macro32's output for
# VaxVarRecords.mod and the module it imports, VaxRecLib.mod, against the
# reviewed expected-vax.mar and expected-vax-VaxRecLib.mar, assembled and
# run under the debugger on the VAX where the development system can be
# used (../../vaxfixture.sh): what it computes, and the tags passed. Then,
# for -O2 and -OC, VarRecOut built by the LLVM backend and run here, and
# built for the VAX and run there (vax_do): both must print
# output.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f VarRecOut.com
: >result
vax_mar VaxVarRecords
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-var-records -build VarRecOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-var-records >output 2>&1
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build VarRecOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  { echo "build status: %X10000001"; cat output.expected; echo "run status: %X00000001"; } >guest-run.expected
  vax_do guest-run.com guest-run.expected VarRecOut.com VarRecOut.mar VaxRecLib.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar $rtl/PocRtl.mar
done
}
vax_build builds
rm -f output guest-run.expected *.obj
. ../../testresult.sh
