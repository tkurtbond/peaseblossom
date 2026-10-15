#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 (doc/developer/vax-macro32-backend.md, section 20,
# proposals 1, 6 and 10): the run-time checks on the unsigned types on
# VAX/VMS. llvm-cardinal-traps' four programs, built for the VAX under
# -O2 and -range-checks and run there (vax_do, guest-run.com), each with
# SYS$ERROR a file typed after it: each prints "A", then traps before it
# can print "B", with the status and the message guest-run.expected has
# (2, a CARD64 index above MAX(HUGEINT) and a CARD8 index of 200 in an
# open array of 200; 14, SHORT of a CARD16 of 256 and CHR of one).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
programs="bigindex openindex shortrange chrrange"
written="Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar GarbageCollectedHeap.mar"
: >result
for name in $programs; do
  cp ../llvm-cardinal-traps/$name.mod .
  rm -f *.sym $name.com
  poc -range-checks -target vax-dec-vms -import-path $rtl -build $name.mod >>result 2>&1
  echo "VAX build $name exit $?" >>result
done
vax_do guest-run.com guest-run.expected bigindex.com openindex.com shortrange.com chrrange.com \
  bigindex.mar openindex.mar shortrange.mar chrrange.mar $written $rtl/PocRtl.mar
for name in $programs; do rm -f $name.mod $name.mar $name.com; done
rm -f *.sym $written
. ../../testresult.sh
