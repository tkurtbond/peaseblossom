#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.17, proposals 1 and 4): Args on VAX/VMS, with llvm-args' argstest.mod,
# built for the VAX under -O2 and run there as a foreign command with
# "alpha" "" 42 -7 "x9" (quoted where DCL would make them upper case),
# ARGSTEST_SET defined as a process logical name (vax_do, guest-run.com).
# It must print llvm-args' expected, but that a logical name cannot be
# defined empty, so ARGSTEST_EMPTY is not set.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="argstest.mar Args.mar Modules.mar Platform.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
cp ../llvm-args/argstest.mod .
rm -f argstest.com
: >result
rm -f *.sym $written
poc -target vax-dec-vms -import-path $rtl -build argstest.mod >>result 2>&1
echo "VAX build argstest exit $?" >>result
vax_do guest-run.com guest-run.expected argstest.com $written $rtl/PocRtl.mar
rm -f *.sym $written argstest.com argstest.mod
. ../../testresult.sh
