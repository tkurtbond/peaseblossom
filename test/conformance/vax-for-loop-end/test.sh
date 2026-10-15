#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 (doc/developer/vax-macro32-backend.md, section 20,
# proposals 8 and 10): every FOR loop ends before a step that would pass
# its final value, on VAX/VMS. llvm-for-loop-end's forend.mod, built for
# the VAX under -O2: its MACRO-32 must be the reviewed expected-vax.mar,
# and run on the guest (vax_do, guest-run.com) it must print
# llvm-for-loop-end's expected.
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
vax_do guest-run.com guest-run.expected forend.com $written $rtl/PocRtl.mar
rm -f *.sym $written forend.com forend.mod guest-run.expected
. ../../testresult.sh
