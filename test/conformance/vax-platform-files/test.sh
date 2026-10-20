#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.1): rtl/vax's Platform on VAX/VMS. For -O2 and -OC, PlatformFiles
# built for the VAX and run there (vax_do, guest-run.com), which must
# print guest-run.expected: files by handle, identities and times, the
# error tests, the clock, logical names, memory, the default directory,
# a command in a subprocess, and standard input and output.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f PlatformFiles.com
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
for model in -O2 -OC; do
  rm -f *.sym *.mar
  poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build PlatformFiles.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected PlatformFiles.com PlatformFiles.mar Platform.mar Out.mar \
    LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar $rtl/PocRtl.mar
done
}
vax_build builds
rm -f *.sym *.mar PlatformFiles.com *.obj
. ../../testresult.sh
