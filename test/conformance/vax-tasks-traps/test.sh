#!/bin/sh
. ../../testenv.sh
# Tasks on VAX/VMS (doc/developer/tasks.md, Phase 9), the cases of
# llvm-tasks-traps but its signal handler's (see TaskTraps.mod): 19 (all
# tasks blocked), each case of 20 (misuse), whose texts PocRtl.mar's
# POC_TRAP finds by the case in the code's high word, and 17 (a Yield in a
# finalizer); each with a finalizer run, and its status. Built by poc
# -build with -link COROUTINESWITCH.OBJ and run on the guest (vax_do),
# both ways (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
modules="TaskTraps Tasks TaskWaiting Coroutines GarbageCollectedHeap Platform Modules Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
rm -f TaskTraps.com
: >result
builds() {
rm -f $symbols $written
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build TaskTraps.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected TaskTraps.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects TaskTraps.com
. ../../testresult.sh
