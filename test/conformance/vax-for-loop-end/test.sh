#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 (doc/developer/vax-macro32-backend.md, section 20,
# proposals 8 and 10): every FOR loop ends before a step that would pass
# its final value, on VAX/VMS. llvm-for-loop-end's forend.mod, built for
# the VAX under -O2: its MACRO-32 must be the reviewed expected-vax.mar,
# and run on the guest (vax_do, guest-run.com) it must print
# llvm-for-loop-end's expected. Phase 18 step 4d: and so must the
# program linked from the objects poc wrote, sent and converted by
# tools/vax-do, with poc's runtime from MACRO (guest-link.com).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="forend.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
cp ../llvm-for-loop-end/forend.mod .
{
  echo "build status: %X10000001"
  cat ../llvm-for-loop-end/expected
  echo "run status: %X00000001"
} >guest-run.expected
: >result
rm -f *.sym $written forend.com
poc -target vax-dec-vms -import-path $rtl -build forend.mod >>result 2>&1
echo "VAX build forend exit $?" >>result
vax_compare forend.mar expected-vax.mar
poc -target vax-dec-vms -import-path $rtl -emit-vax-object forend.mod >/dev/null 2>>result
echo "VAX image forend exit $?" >>result
vax_object_image forend
vax_image_compare forend.image expected-vax.image
vax_do guest-run.com guest-run.expected forend.com $written $rtl/PocRtl.mar
# Phase 18 step 4d: the same program linked from the objects poc wrote,
# with only poc's runtime assembled by MACRO, must print the same
vax_do guest-link.com guest-run.expected $(echo "$written" | sed 's/\.mar/.obj/g') $rtl/PocRtl.mar
rm -f *.sym $written $(echo "$written" | sed 's/\.mar/.image/g') $(echo "$written" | sed 's/\.mar/.obj/g') forend.com forend.mod guest-run.expected
. ../../testresult.sh
