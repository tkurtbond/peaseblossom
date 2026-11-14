#!/bin/sh
. ../../testenv.sh
# Coroutines on VAX/VMS (doc/developer/coroutines.md, Phase 4): a
# traceback in a coroutine (see CoroutineTrace.mod) lists its routines,
# with their lines, down to Coroutines' Start and ends at
# POC_COROUTINE_START, the switch's routine that starts every new stack.
# Built by poc -build with -link COROUTINESWITCH.OBJ, the switch, which
# guest-run.com assembles from rtl/vax/CoroutineSwitch.mar, and run on the
# guest (vax_do), with the code addresses masked (vax_mask). Only poc's
# own objects, not vax_build's two ways: MACRO's objects carry no line
# numbers and name a routine by its mangled symbol, and the switch's last
# frame by its psect, POC_CODE, so the traceback differs by the way.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
modules="CoroutineTrace Coroutines GarbageCollectedHeap Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
rm -f CoroutineTrace.com $symbols $written $objects
: >result
vax_mask=yes
vax_way=objects; vax_way_option=-vax-objects
touch vax-way.stamp
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build CoroutineTrace.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected CoroutineTrace.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
rm -f vax-way.stamp $symbols $written $objects CoroutineTrace.com
unset vax_way vax_way_option
. ../../testresult.sh
