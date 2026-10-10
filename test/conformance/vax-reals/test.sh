#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 9): reals, a REAL an F_floating, a LONGREAL a G_floating. poc
# -emit-macro32's output for VaxReals.mod against the reviewed
# expected-vax.mar, assembled and run under the debugger on the VAX where
# the development system can be used (../../vaxfixture.sh): what it
# computes, how it rounds, and its trap and fault. Then, for -O2 and -OC,
# RealsOut built by the LLVM backend and run here, and built for the VAX
# and run there (vax_do): both must print output.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f RealsOut.com
: >result
vax_mar VaxReals
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-reals -build RealsOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-reals >output 2>&1
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build RealsOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  { echo "build status: %X10000001"; cat output.expected; echo "run status: %X00000001"; } >guest-run.expected
  vax_do guest-run.com guest-run.expected RealsOut.com RealsOut.mar Out.mar LineOutput.mar $rtl/PocRtl.mar
done
rm -f output guest-run.expected
. ../../testresult.sh
