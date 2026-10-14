#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.15, proposals 1 to 5): Math and MathL on VAX/VMS, with llvm-math's
# mathtest.mod and llvm-mathl's mathltest.mod, which check every function
# against Python's values within 1.0E-5, built for the VAX under -O2, as
# the LLVM fixtures are, and run there (vax_do, guest-run.com). They must
# print what they do on LLVM. Only the checks of expoMax and expoMin are
# changed, to F_floating's and G_floating's (proposal 4): they are the
# only ones that state IEEE's ranges.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="mathtest.mar mathltest.mar Math.mar MathL.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
sed -e 's/Math.expoMax, 127)/Math.expoMax, 126)/' -e 's/Math.expoMin, -126)/Math.expoMin, -128)/' \
  ../llvm-math/mathtest.mod >mathtest.mod
sed -e 's/MathL.expoMax, 1023)/MathL.expoMax, 1022)/' -e 's/MathL.expoMin, -1022)/MathL.expoMin, -1024)/' \
  ../llvm-mathl/mathltest.mod >mathltest.mod
rm -f mathtest.com mathltest.com
: >result
rm -f *.sym $written
for program in mathtest mathltest; do
  poc -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1
  echo "VAX build $program exit $?" >>result
done
vax_do guest-run.com guest-run.expected mathtest.com mathltest.com $written $rtl/PocRtl.mar
rm -f *.sym $written mathtest.com mathltest.com mathtest.mod mathltest.mod
. ../../testresult.sh
