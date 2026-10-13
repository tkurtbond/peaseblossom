#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.7, proposals 1, 2 and 6): Out.LongReal and Out.Real on VAX/VMS print
# the correctly rounded digits of G_floating and F_floating values.
# digits.mod and guest-run.expected are written by
# ../llvm-real-digits/generate.py: llvm-real-digits' values that are normal
# in both formats, with the same oracle, and values only the VAX has. For
# -O2 and -OC, built for the VAX and run there (vax_do, guest-run.com).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="digits.mar Out.mar LineOutput.mar FormattedText.mar RealDigits.mar"
rm -f digits.com
: >result
for model in -O2 -OC; do
  rm -f *.sym $written
  poc $model -target vax-dec-vms -import-path $rtl -build digits.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected digits.com $written $rtl/PocRtl.mar
done
rm -f *.sym $written digits.com
. ../../testresult.sh
