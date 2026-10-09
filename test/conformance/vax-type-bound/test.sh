#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 6): type-bound procedures, their ProcTabs, and calls of them
# through a ProcTab, directly and with P^. poc -emit-macro32's output for
# VaxMethods.mod and the module it imports, VaxMethLib.mod, against the
# reviewed expected-vax.mar and expected-vax-VaxMethLib.mar, assembled
# and run under the debugger on the VAX where the development system can
# be used (../../vaxfixture.sh): what it computes, a ProcTab, and its
# traps. Then, for -O2 and -OC, MethodsOut built by the LLVM backend and
# run here, and built for the VAX and run there (vax_do): both must print
# output.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f MethodsOut.com
: >result
vax_mar VaxMethods
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-type-bound -build MethodsOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-type-bound >output 2>&1
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build MethodsOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  { echo "build status: %X10000001"; cat output.expected; echo "run status: %X00000001"; } >guest-run.expected
  vax_do guest-run.com guest-run.expected MethodsOut.com MethodsOut.mar VaxMethLib.mar Out.mar $rtl/PocRtl.mar
done
rm -f output guest-run.expected
. ../../testresult.sh
