#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.3): llvm-files-riders' riders.mod and signed.mod on VAX/VMS. For
# -O2 and -OC, each built for the VAX and run there (vax_do,
# guest-run.com), which must print what llvm-files-riders' expected says
# poc prints on Unix - the typed riders' bytes, IEEE reals included, and
# the Files dropped without Close - with riders.mod's directory names
# made VMS's (riders.sub [.RIDERSSUB], .. [-], . [], the search path's
# ";" ",") and signed's exit
# status 2 the status VMS gives a trap 2 (design section 14, item 10).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
src=../llvm-files-riders
sed -e 's/"nowhere; riders\.sub ;\."/"nowhere, [.RIDERSSUB] ,[]"/' \
    -e 's/ChangeDirectory("riders\.sub"/ChangeDirectory("[.RIDERSSUB]"/' \
    -e 's/ChangeDirectory("\.\."/ChangeDirectory("[-]"/' $src/riders.mod >riders.mod
cp $src/signed.mod signed.mod
rm -f riders.com signed.com
: >result
for model in -O2 -OC; do
  rm -f *.sym *.mar
  for program in riders signed; do
    poc $model -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1
    echo "VAX build $program $model exit $?" >>result
  done
  # llvm-files-riders' expected for this model, without its headings
  awk -v riders="== riders $model" -v signed="== signed $model" '
    /^== / { keep = ($0 == riders || $0 == signed); next }
    keep { if ($0 == "exit=2") print "status: %X10000012"; else print }
  ' $src/expected >guest.expected
  vax_do guest-run.com guest.expected riders.com riders.mar signed.com signed.mar Files.mar Platform.mar \
    GarbageCollectedHeap.mar Out.mar LineOutput.mar $rtl/PocRtl.mar
done
rm -f *.sym *.mar riders.com signed.com riders.mod signed.mod guest.expected
. ../../testresult.sh
