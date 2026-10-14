#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.13, proposals 1 and 2): Strings on VAX/VMS, with llvm-strings'
# stringstest.mod and llvm-strings-extra's stringsextra.mod, built for the
# VAX under -O2, as the LLVM fixtures are, and run there (vax_do,
# guest-run.com). They must print guest-run.expected, which generate.py
# writes: llvm-strings' expected, then llvm-strings-extra's, but for the
# bits of each real Numbers converts, which are F_floating's and
# G_floating's, 1.7976931348623157E308 becoming G's largest value and
# 4.9E-324 becoming 0.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="stringstest.mar stringsextra.mar Strings.mar DecimalToReal.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
cp ../llvm-strings/stringstest.mod ../llvm-strings-extra/stringsextra.mod .
rm -f stringstest.com stringsextra.com
: >result
rm -f *.sym $written
for program in stringstest stringsextra; do
  poc -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1
  echo "VAX build $program exit $?" >>result
done
vax_do guest-run.com guest-run.expected stringstest.com stringsextra.com $written $rtl/PocRtl.mar
rm -f *.sym $written stringstest.com stringsextra.com stringstest.mod stringsextra.mod
. ../../testresult.sh
