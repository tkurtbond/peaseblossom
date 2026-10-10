#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 8): nested procedures, lifted with the addresses of the
# enclosing procedures' variables they need. poc -emit-macro32's output
# for VaxNested.mod against the reviewed expected-vax.mar, assembled and
# run under the debugger on the VAX where the development system can be
# used (../../vaxfixture.sh): what it computes, and its traps. Then, for
# -O2 and -OC, NestedOut built by the LLVM backend and run here, and
# built for the VAX and run there (vax_do): both must print
# output.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f NestedOut.com
: >result
vax_mar VaxNested
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-nested -build NestedOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-nested >output 2>&1
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build NestedOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  { echo "build status: %X10000001"; cat output.expected; echo "run status: %X00000001"; } >guest-run.expected
  vax_do guest-run.com guest-run.expected NestedOut.com NestedOut.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar $rtl/PocRtl.mar
done
rm -f output guest-run.expected
. ../../testresult.sh
