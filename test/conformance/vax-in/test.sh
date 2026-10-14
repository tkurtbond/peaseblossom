#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.11, proposals 1, 2 and 5): In on VAX/VMS, reading SYS$INPUT through
# Platform.Read(StdIn). llvm-in's intest.mod and input.txt, and prompt.mod,
# built for the VAX under -O2, as llvm-in is, and run there (vax_do,
# guest-run.com) with SYS$INPUT their input files: intest must print
# llvm-in's expected, and prompt "count? 42" on one line, its prompt kept in
# Out's line since SYS$INPUT is not a terminal.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="intest.mar prompt.mar In.mar FormattedInput.mar DecimalToReal.mar Platform.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
cp ../llvm-in/intest.mod ../llvm-in/input.txt .
rm -f intest.com prompt.com
: >result
rm -f *.sym $written
for program in intest prompt; do
  poc -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1
  echo "VAX build $program exit $?" >>result
done
vax_do guest-run.com guest-run.expected intest.com prompt.com input.txt prompt.txt $written $rtl/PocRtl.mar
rm -f *.sym $written intest.com prompt.com intest.mod input.txt
. ../../testresult.sh
