#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 (doc/developer/vax-macro32-backend.md, section 20,
# proposal 10): the unsigned types on VAX/VMS. llvm-cardinal's
# cardinal.mod, built for the VAX under -O2: its MACRO-32 must be the
# reviewed expected-vax.mar, and run on the guest (vax_do,
# guest-run.com) it must print llvm-cardinal's expected, Err's line
# included, which SYS$ERROR writes to the same terminal.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="cardinal.mar CardinalTypes.mar DecimalToReal.mar Err.mar FormattedInput.mar FormattedOutput.mar FormattedText.mar InStr.mar LineOutput.mar Out.mar OutStr.mar RealDigits.mar"
cp ../llvm-cardinal/cardinal.mod .
{
  echo "build status: %X10000001"
  grep -v '^18446744073709551614 FFFFFFFFFFFFFFFE$' ../llvm-cardinal/expected
  echo "run status: %X00000001"
  echo "-- SYS\$ERROR"
  grep '^18446744073709551614 FFFFFFFFFFFFFFFE$' ../llvm-cardinal/expected
} >guest-run.expected
: >result
rm -f *.sym $written cardinal.com
poc -target vax-dec-vms -import-path $rtl -build cardinal.mod >>result 2>&1
echo "VAX build cardinal exit $?" >>result
vax_compare cardinal.mar expected-vax.mar
poc -target vax-dec-vms -import-path $rtl -emit-vax-object cardinal.mod >/dev/null 2>>result
echo "VAX image cardinal exit $?" >>result
vax_object_image cardinal
vax_image_compare cardinal.image expected-vax.image
vax_do guest-run.com guest-run.expected cardinal.com $written $rtl/PocRtl.mar
rm -f *.sym $written $(echo "$written" | sed 's/\.mar/.image/g') $(echo "$written" | sed 's/\.mar/.obj/g') cardinal.com cardinal.mod guest-run.expected
. ../../testresult.sh
