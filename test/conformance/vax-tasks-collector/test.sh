#!/bin/sh
. ../../testenv.sh
# Tasks on VAX/VMS (doc/developer/tasks.md, Phase 9), the program of
# llvm-tasks-collector (see TaskCollector.mod): lists held only by blocked
# tasks, waiting senders and tasks only Tasks' queues point to survive
# main's collections. Built by poc -build with -link COROUTINESWITCH.OBJ
# and run on the guest (vax_do), both ways (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
modules="TaskCollector Tasks TaskWaiting Coroutines GarbageCollectedHeap Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
rm -f TaskCollector.com
: >result
builds() {
rm -f $symbols $written
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build TaskCollector.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected TaskCollector.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects TaskCollector.com
. ../../testresult.sh
