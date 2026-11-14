#!/bin/sh
. ../../testenv.sh
# Coroutines on VAX/VMS (doc/developer/coroutines.md, Phase 4): a timer
# AST allocates while coroutines switch and collections scan their stacks
# (see CoroutineAsts.mod); run three times on the guest (guest-run.com),
# or VAX_REPEAT times each (make test-vax-asts), as an interruption at
# the wrong instruction is a matter of chance. Built by poc -build with
# -link COROUTINESWITCH.OBJ, the switch, which guest-run.com assembles
# from rtl/vax/CoroutineSwitch.mar, and run on the guest (vax_do), both
# ways (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
modules="CoroutineAsts Coroutines AsynchronousTraps GarbageCollectedHeap Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
rm -f CoroutineAsts.com
: >result
builds() {
rm -f $symbols $written
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build CoroutineAsts.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected CoroutineAsts.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects CoroutineAsts.com
. ../../testresult.sh
