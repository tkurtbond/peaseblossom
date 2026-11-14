#!/bin/sh
. ../../testenv.sh
# Tasks on VAX/VMS (doc/developer/tasks.md, Phase 9), the programs of
# llvm-tasks (with 2000 short tasks, not 20000), llvm-tasks-channels and
# llvm-tasks-sync, renamed so that none is named as a runtime module is on
# a system whose file names ignore case. Built by poc -build with -link
# COROUTINESWITCH.OBJ, which guest-run.com assembles from
# rtl/vax/CoroutineSwitch.mar, and run on the guest (vax_do), both ways
# (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
programs="TaskBasics TaskChannels TaskSync"
modules="$programs Tasks TaskWaiting Coroutines GarbageCollectedHeap Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=; scripts=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
for p in $programs; do scripts="$scripts $p.com"; done
rm -f $scripts
: >result
builds() {
rm -f $symbols $written
for program in $programs; do
  poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build $program.mod >>result 2>&1
  echo "VAX build of $program exit $?" >>result
done
vax_do guest-run.com guest-run.expected $scripts $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects $scripts
. ../../testresult.sh
