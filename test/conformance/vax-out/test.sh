#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 2): rtl/vax's minimal Out. poc -emit-macro32's output for
# OutBasics.mod and rtl/vax/Out.Mod, against the reviewed expected-vax.mar
# and expected-vax-Out.mar, assembled and run under the debugger on the VAX
# where the development system can be used (../../vaxfixture.sh). Then, for
# -O2 and -OC, OutBasics built by the LLVM backend (Out from poc-rtl) and
# run here, and built for the VAX and run there (vax_do): both must print
# output<model>.expected. OutUnfinished's line without Ln is written on the
# VAX too, by the exit handler.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f OutBasics.com OutUnfinished.com
: >result
vax_mar OutBasics -import-path $rtl
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-out -build OutBasics.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-out >output 2>&1
  cmp -s output output$model.expected || { echo "the LLVM backend's output, $model:" >>result; diff output$model.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build OutBasics.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  { echo "build status: %X10000001"; cat output$model.expected; echo "run status: %X00000001"; } >guest-run.expected
  vax_do guest-run.com guest-run.expected OutBasics.com OutBasics.mar Out.mar $rtl/PocRtl.mar
done
rm -f *.sym
poc -target vax-dec-vms -import-path $rtl -build OutUnfinished.mod >>result 2>&1
echo "VAX build OutUnfinished exit $?" >>result
vax_do guest-unfinished.com guest-unfinished.expected OutUnfinished.com OutUnfinished.mar Out.mar $rtl/PocRtl.mar
rm -f output guest-run.expected
. ../../testresult.sh
