#!/bin/sh
. ../../testenv.sh
# Coroutines on VAX/VMS (doc/developer/coroutines.md, Phase 4), the program
# of llvm-coroutines-free (see CoroutineFree.mod). Built by poc -build with -link
# COROUTINESWITCH.OBJ, the switch, which guest-run.com assembles from
# rtl/vax/CoroutineSwitch.mar, and run on the guest (vax_do), both ways
# (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
modules="CoroutineFree Coroutines GarbageCollectedHeap Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
rm -f CoroutineFree.com
: >result
builds() {
rm -f $symbols $written
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build CoroutineFree.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected CoroutineFree.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects CoroutineFree.com
. ../../testresult.sh
