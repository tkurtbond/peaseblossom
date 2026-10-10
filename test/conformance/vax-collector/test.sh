#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
# 15, proposal 9): rtl/vax's GarbageCollectedHeap. poc -emit-macro32's
# output for CollectUse.mod and rtl/vax/GarbageCollectedHeap.Mod against
# the reviewed expected-vax.mar and expected-vax-GarbageCollectedHeap.mar,
# assembled on the VAX where the development system can be used
# (../../vaxfixture.sh). Then, for -O2 and -OC, CollectOut built by the
# LLVM backend and run here, and built for the VAX and run there (vax_do,
# guest-run.com): both must print output.expected. Last, HeapCeiling,
# built for the VAX only and run there (guest-ceiling.com), whose heap
# must stop at the ceiling taken from the paging file quota.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f CollectOut.com HeapCeiling.com
: >result
vax_mar CollectUse -import-path $rtl
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-collector -build CollectOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-collector >output 2>&1
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build CollectOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  { echo "build status: %X10000001"; cat output.expected; echo "run status: %X00000001"; } >guest-run.expected
  vax_do guest-run.com guest-run.expected CollectOut.com CollectOut.mar GarbageCollectedHeap.mar \
    Out.mar LineOutput.mar $rtl/PocRtl.mar
done
rm -f *.sym
poc -target vax-dec-vms -import-path $rtl -build HeapCeiling.mod >>result 2>&1
echo "VAX build HeapCeiling exit $?" >>result
vax_do guest-ceiling.com guest-ceiling.expected HeapCeiling.com HeapCeiling.mar GarbageCollectedHeap.mar \
  Out.mar LineOutput.mar $rtl/PocRtl.mar
rm -f output guest-run.expected
. ../../testresult.sh
