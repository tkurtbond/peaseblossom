#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.17, proposals 3 and 4): VT100 on VAX/VMS, with llvm-vt100's
# vt100same.mod and vt100diff.mod, built for the VAX under -O2 and -OC and
# run there with their output to a file (vax_do, guest-run.com). They must
# write llvm-vt100's bytes, a record for each line they end: what
# llvm-vt100's expected shows for the model (cat -v's ^[ and ^V made ESC
# and SYN again), between the procedure's own lines. Out.Flush, which VT100
# calls after each sequence, does nothing to a file.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="vt100same.mar vt100diff.mar VT100.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
programs="vt100same vt100diff"
cp ../llvm-vt100/vt100same.mod ../llvm-vt100/vt100diff.mod .
rm -f vt100same.com vt100diff.com
esc=$(printf '\033'); syn=$(printf '\026')
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
for model in -O2 -OC; do
  rm -f *.sym $written
  for p in $programs; do
    poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build $p.mod >>result 2>&1
    echo "VAX build $p $model exit $?" >>result
  done
  # llvm-vt100's lines for the model, as the guest prints them
  awk -v model="$model" '
    /^== / { split($0, f, " "); keep = (f[2] == model); if (keep) { if (f[3] == "vt100diff") print "run status: %X00000001"; print "== " f[3] } ; next }
    keep { print }
  ' ../llvm-vt100/expected | sed -e "s/\^\[/$esc/g" -e "s/\^V/$syn/g" >vt100-printed
  { echo 'build status: %X10000001'; cat vt100-printed; echo 'run status: %X00000001'; } >vt100.expected
  vax_do guest-run.com vt100.expected vt100same.com vt100diff.com $written $rtl/PocRtl.mar
done
}
vax_build builds
rm -f *.sym $written vt100same.com vt100diff.com vt100same.mod vt100diff.mod vt100-printed vt100.expected *.obj
. ../../testresult.sh
