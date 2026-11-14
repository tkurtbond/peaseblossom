#!/bin/sh
. ../../testenv.sh
# The User's Guide's coroutine examples on VAX/VMS (doc/developer/
# coroutines.md, Phase 5): WordSets and Queens, from doc/examples/
# coroutines, unchanged, built by poc -build with -link COROUTINESWITCH.OBJ
# (as vax-coroutines is) and run on the guest as foreign commands, both
# ways (vax_build): WordSets with the guide's two files and with too few
# arguments, Queens with the guide's arguments and with other sizes, in
# capitals as DCL passes them, and with a size it refuses. What they print
# is what they print on Unix (doc-users-guide checks the guide's runs
# there), each followed by its $STATUS.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
examples=../../../doc/examples/coroutines
copied="WordSets.Mod Queens.Mod memo.txt words.txt"
written="WordSets.mar Queens.mar Coroutines.mar GarbageCollectedHeap.mar LineOutput.mar Platform.mar Files.mar Modules.mar Args.mar DecimalToReal.mar FormattedInput.mar In.mar RealDigits.mar FormattedText.mar FormattedOutput.mar Out.mar"
symbols="WordSets.sym Queens.sym Coroutines.sym GarbageCollectedHeap.sym LineOutput.sym Platform.sym Files.sym Modules.sym Args.sym DecimalToReal.sym FormattedInput.sym In.sym RealDigits.sym FormattedText.sym FormattedOutput.sym Out.sym"
objects="WordSets.obj Queens.obj Coroutines.obj GarbageCollectedHeap.obj LineOutput.obj Platform.obj Files.obj Modules.obj Args.obj DecimalToReal.obj FormattedInput.obj In.obj RealDigits.obj FormattedText.obj FormattedOutput.obj Out.obj"
rm -f WordSets.com Queens.com
for f in $copied; do cp $examples/$f $f; done
: >result
builds() {
rm -f $symbols $written
for program in WordSets Queens; do
  poc -target vax-dec-vms $vax_way_option -import-path $rtl -link COROUTINESWITCH.OBJ -build $program.Mod >>result 2>&1
  echo "VAX build of $program exit $?" >>result
done
vax_do guest-run.com guest-run.expected WordSets.com Queens.com memo.txt words.txt $written $rtl/PocRtl.mar $rtl/CoroutineSwitch.mar
}
vax_build builds
rm -f $symbols $written $objects $copied WordSets.com Queens.com
. ../../testresult.sh
