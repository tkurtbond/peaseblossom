#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.11, proposals 4 and 5): InStr on VAX/VMS. rtl/vax/InStr.Mod must be
# rtl/llvm's, but for its one line saying it is a copy. llvm-instr's
# instr.mod, as InStrUse.mod since VMS does not tell instr from InStr,
# built for the VAX under -O2 and -OC and run there (vax_do,
# guest-run.com) as a foreign command with "in" and with "instr", SYS$INPUT
# llvm-instr's input.txt. With "instr" it must print llvm-instr's
# expected; with "in", the same up to "-- InStr only" without the "pos"
# lines, which is what llvm-instr checks In and InStr agree on.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="InStrUse.mar In.mar InStr.mar FormattedInput.mar DecimalToReal.mar Platform.mar Modules.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
grep -v '^  (\* rtl/vax: a copy of rtl/llvm/InStr.Mod' $rtl/InStr.Mod >InStr.copy
cmp -s InStr.copy ../../../rtl/llvm/InStr.Mod || echo "rtl/vax/InStr.Mod is not rtl/llvm's" >>result
rm -f InStr.copy
sed -e 's/^MODULE instr;/MODULE InStrUse;/' -e 's/^END instr\./END InStrUse./' ../llvm-instr/instr.mod >InStrUse.mod
cp ../llvm-instr/input.txt .
{
  echo "build status: %X10000001"
  echo "== in"
  sed '/^-- InStr only/,$d' ../llvm-instr/expected | grep -v '^pos '
  echo "run status: %X00000001"
  echo "== instr"
  cat ../llvm-instr/expected
  echo "run status: %X00000001"
} >guest-run.expected
rm -f InStrUse.com
for model in -O2 -OC; do
  rm -f *.sym $written
  poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build InStrUse.mod >>result 2>&1
  echo "VAX build InStrUse $model exit $?" >>result
  vax_do guest-run.com guest-run.expected InStrUse.com input.txt $written $rtl/PocRtl.mar
done
}
vax_build builds
rm -f *.sym $written InStrUse.com InStrUse.mod input.txt guest-run.expected *.obj
. ../../testresult.sh
