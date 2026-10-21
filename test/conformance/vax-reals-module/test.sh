#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.7, proposals 4 to 6): rtl/vax's Reals, with llvm-reals-module's
# reals.mod, as RealsUse.mod, since VMS does not tell the program reals
# from the module Reals, and beyond.mod. For -O2 and -OC, both built for
# the VAX and run there (vax_do, guest-run.com), which must print guest-run.expected:
# F_floating's and G_floating's bytes, exponent fields and ranges, written
# by generate.py from the formats' definitions, not by running the
# programs (generate.py ieee checks the same model against what they print
# on Unix).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="RealsUse.mar beyond.mar Reals.mar DecimalToReal.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
sed -e 's/^MODULE reals;/MODULE RealsUse;/' -e 's/^END reals\./END RealsUse./' ../llvm-reals-module/reals.mod >RealsUse.mod
cp ../llvm-reals-module/beyond.mod .
rm -f RealsUse.com beyond.com
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
for model in -O2 -OC; do
  rm -f *.sym $written
  for program in RealsUse beyond; do
    poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build $program.mod >>result 2>&1
    echo "VAX build $program $model exit $?" >>result
  done
  vax_do guest-run.com guest-run.expected RealsUse.com beyond.com $written $rtl/PocRtl.mar
done
}
vax_build builds
rm -f *.sym $written RealsUse.com beyond.com RealsUse.mod beyond.mod *.obj
. ../../testresult.sh
