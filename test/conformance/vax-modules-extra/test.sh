#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.5, proposal 8): rtl/vax's Modules, the parts of its command line
# specific to poc. For -O2 and -OC, llvm-modules-extra's modulesextra.mod,
# with its long argument 200 zeros, as a DCL command line takes, rather
# than 3000, and ArgVector.mod, built for the VAX and run there as foreign
# commands (vax_do, guest-run.com), which must print guest-run.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
sed -e 's/3000/200/g' ../llvm-modules-extra/modulesextra.mod >modulesextra.mod
rm -f modulesextra.com ArgVector.com
: >result
for model in -O2 -OC; do
  rm -f *.sym *.mar
  for program in modulesextra ArgVector; do
    poc $model -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1
    echo "VAX build $program $model exit $?" >>result
  done
  vax_do guest-run.com guest-run.expected modulesextra.com ArgVector.com modulesextra.mar ArgVector.mar \
    Modules.mar Console.mar Out.mar LineOutput.mar FormattedText.mar RealDigits.mar Platform.mar GarbageCollectedHeap.mar $rtl/PocRtl.mar
done
rm -f *.sym *.mar modulesextra.com ArgVector.com modulesextra.mod
. ../../testresult.sh
