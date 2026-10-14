#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.15, proposal 5): Math and MathL where VAX/VMS differs from LLVM, in
# place of llvm-math-extra - F_floating's and G_floating's bit patterns
# of the constants, the ends of the range, succ and pred with no
# denormals, MTH$'s and OTS$'s overflows as Overflow and +-large, large
# arguments to sin, cos and tan, arcsinh and arccosh - built for the VAX
# under -O2 and run there (vax_do, guest-run.com).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="vaxmathextra.mar Math.mar MathL.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
rm -f vaxmathextra.com
: >result
rm -f *.sym $written
poc -target vax-dec-vms -import-path $rtl -build vaxmathextra.mod >>result 2>&1
echo "VAX build vaxmathextra exit $?" >>result
vax_do guest-run.com guest-run.expected vaxmathextra.com $written $rtl/PocRtl.mar
rm -f *.sym $written vaxmathextra.com
. ../../testresult.sh
