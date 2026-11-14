#!/bin/sh
. ../../testenv.sh
# Coroutines on VAX/VMS (doc/developer/coroutines.md, Phase 4), the cases
# of llvm-coroutines-traps: trap 16 (a body returns); each case of 17 (a
# Transfer to a record never given to Init, to a freed coroutine, in a
# finalizer, in an AST; a Free of the running coroutine, of main's); 18
# (Init refused its stack: MAX(LONGINT) bytes, and stacks of 1 MiB never
# freed, until the page-file quota is spent); a NIL dereference, HALT and
# ASSERT on a coroutine, and a NIL body; each with a finalizer run, and
# its status. And a stack overflow, which ends in an access violation
# (concurrency-survey.md, section 8.7, item 7). Built by poc -build with
# -link COROUTINESWITCH.OBJ and run on the guest (vax_do), both ways
# (vax_build).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
modules="CoroutineTraps Coroutines GarbageCollectedHeap AsynchronousTraps Platform Modules Out LineOutput FormattedOutput FormattedText RealDigits"
written=; symbols=; objects=
for m in $modules; do written="$written $m.mar"; symbols="$symbols $m.sym"; objects="$objects $m.obj"; done
rm -f CoroutineTraps.com
: >result
builds() {
rm -f $symbols $written
poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build CoroutineTraps.mod >>result 2>&1
echo "VAX build exit $?" >>result
vax_do guest-run.com guest-run.expected CoroutineTraps.com $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects CoroutineTraps.com
. ../../testresult.sh
