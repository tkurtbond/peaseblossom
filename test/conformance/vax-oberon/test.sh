#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.19, proposals 2 and 4): Oberon on VAX/VMS, with llvm-oberon's
# oberon.mod, as OberonUse.mod since VMS does not tell oberon from Oberon,
# and beyond.mod, built for the VAX under -O2 and -OC and run there as
# foreign commands (vax_do, guest-run.com). They must print what
# llvm-oberon's expected shows for the model, but that beyond's argument
# is 200 characters, not 300, since DCL takes a command line of at most
# 255: "par 201".
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="OberonUse.mar beyond.mar Oberon.mar Texts.mar Files.mar Modules.mar Platform.mar GarbageCollectedHeap.mar DecimalToReal.mar Reals.mar RealDigits.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar"
sed -e 's/^MODULE oberon;/MODULE OberonUse;/' -e 's/^END oberon\./END OberonUse./' \
  ../llvm-oberon/oberon.mod >OberonUse.mod
cp ../llvm-oberon/beyond.mod .
rm -f OberonUse.com beyond.com
: >result
for model in -O2 -OC; do
  rm -f *.sym $written
  for p in OberonUse beyond; do
    poc $model -target vax-dec-vms -import-path $rtl -build $p.mod >>result 2>&1
    echo "VAX build $p $model exit $?" >>result
  done
  # llvm-oberon's lines for the model, as the guest prints them
  {
    echo 'build status: %X10000001'
    awk -v model="$model" '
      /^== / { if (keep) print "run status: %X00000001"; keep = ($3 == model); if (keep) print "== " $2; next }
      /^exit=/ { next }
      keep && /^par 301$/ { print "par 201"; next }
      keep { print }
      END { if (keep) print "run status: %X00000001" }
    ' ../llvm-oberon/expected
  } >oberon.expected
  vax_do guest-run.com oberon.expected OberonUse.com beyond.com $written $rtl/PocRtl.mar
done
rm -f *.sym $written OberonUse.com beyond.com OberonUse.mod beyond.mod oberon.expected
. ../../testresult.sh
