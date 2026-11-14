#!/bin/sh
. ../../testenv.sh
# Coroutines on VAX/VMS (doc/developer/coroutines.md, Phase 4), the
# program of llvm-coroutines: a generator, a copied record, Transfer to the
# running coroutine, main resumed by a coroutine other than the one it last
# resumed, a recursion on a coroutine's stack. Built by poc -build with
# -link COROUTINESWITCH.OBJ, the switch, which guest-run.com assembles
# from rtl/vax/CoroutineSwitch.mar, and run on the guest (vax_do), both
# ways (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="CoroutineBasics.mar Coroutines.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
symbols="CoroutineBasics.sym Coroutines.sym GarbageCollectedHeap.sym Out.sym LineOutput.sym FormattedOutput.sym FormattedText.sym RealDigits.sym"
objects="CoroutineBasics.obj Coroutines.obj GarbageCollectedHeap.obj Out.obj LineOutput.obj FormattedOutput.obj FormattedText.obj RealDigits.obj"
rm -f CoroutineBasics.com
: >result
builds() {
rm -f $symbols $written
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build CoroutineBasics.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected CoroutineBasics.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects CoroutineBasics.com
. ../../testresult.sh
