#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.9, proposals 3 and 4): OutStr on VAX/VMS. rtl/vax/OutStr.Mod must be
# rtl/llvm's, but for its one line saying it is a copy. llvm-outstr's
# outstr.mod, as OutStrUse.mod since VMS does not tell outstr from
# OutStr, without the lines that build a value from IEEE 754's bits (a
# subnormal, the infinities, the NaNs), and with MAX and MIN of REAL and
# LONGREAL, F_floating's and G_floating's largest, in their place. For
# -O2 and -OC, built for the VAX and run there (vax_do, guest-run.com),
# it must print guest-run.expected: llvm-outstr's expected, but for those
# lines. As in llvm-outstr, each line Out wrote must be the same as the
# OutStr string after it (pairs of lines ending "|"), which is checked in
# guest-run.expected, so it holds on the guest when the output matches.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="OutStrUse.mar Out.mar OutStr.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
grep -v '^  (\* rtl/vax: a copy of rtl/llvm/OutStr.Mod' $rtl/OutStr.Mod >OutStr.copy
cmp -s OutStr.copy ../../../rtl/llvm/OutStr.Mod || echo "rtl/vax/OutStr.Mod is not rtl/llvm's" >>result
rm -f OutStr.copy
awk '/bits32 := |bits64 := /{next}
  {sub(/^MODULE outstr;/, "MODULE OutStrUse;"); sub(/^END outstr\./, "END OutStrUse."); print}
  /^  Real\(123456789\.0, 20\);/{print "  Real(MAX(REAL), 16); Real(MIN(REAL), 16);"}
  /^  LongReal\(6\.02214076D23, 30\);/{print "  LongReal(MAX(LONGREAL), 25); LongReal(MIN(LONGREAL), 25);"}' \
  ../llvm-outstr/outstr.mod >OutStrUse.mod
awk '/\|$/ { if (n % 2 == 0) first = $0; else if ($0 != first) print "differs: " first " / " $0; n++ }' guest-run.expected >>result
rm -f OutStrUse.com
for model in -O2 -OC; do
  rm -f *.sym $written
  poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build OutStrUse.mod >>result 2>&1
  echo "VAX build OutStrUse $model exit $?" >>result
  vax_do guest-run.com guest-run.expected OutStrUse.com $written $rtl/PocRtl.mar
done
}
vax_build builds
rm -f *.sym $written OutStrUse.com OutStrUse.mod *.obj
. ../../testresult.sh
