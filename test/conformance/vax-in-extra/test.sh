#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.11, proposals 3 and 5): In's tokens and reals on VAX/VMS, with
# llvm-in-extra's inextra.mod, built for the VAX under -O2, as
# llvm-in-extra is, and run there (vax_do, guest-run.com) with SYS$INPUT
# llvm-in-extra's input.txt without its two CRs, since a VMS record has no
# line-end characters: "windows line" and an empty line. It must print
# guest-run.expected, which generate.py writes: llvm-in-extra's expected,
# but for the bits of each real read, which are F_floating's and
# G_floating's, 1.7976931348623157E308 becoming G's largest value and
# 4.9E-324 becoming 0.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="inextra.mar In.mar FormattedInput.mar DecimalToReal.mar Platform.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
cp ../llvm-in-extra/inextra.mod .
tr -d '\r' <../llvm-in-extra/input.txt >input.txt
rm -f inextra.com
: >result
rm -f *.sym $written
poc -target vax-dec-vms -import-path $rtl -build inextra.mod >>result 2>&1
echo "VAX build inextra exit $?" >>result
vax_do guest-run.com guest-run.expected inextra.com input.txt $written $rtl/PocRtl.mar
rm -f *.sym $written inextra.com inextra.mod input.txt
. ../../testresult.sh
