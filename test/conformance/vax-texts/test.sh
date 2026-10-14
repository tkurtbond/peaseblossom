#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.19, proposals 1 and 4): Texts on VAX/VMS, with llvm-texts' texts.mod
# as TextsUse.mod, since VMS does not tell texts from Texts, its elements
# naming that module too; built for the VAX under -O2 and run there
# (vax_do, guest-run.com). It must print llvm-texts' expected, but that a
# real number's bytes are F_floating's or G_floating's (vax-reals.sed).
# Close keeps no .Bak there: plain.Text, closed twice, must be two
# versions. The files it writes are dumped by FileBytes.mod, since
# tools/vax-do brings back text only, and must be the bytes TextsUse.mod
# built by poc for this host writes, as od shows them.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="TextsUse.mar FileBytes.mar Texts.mar Files.mar Modules.mar Platform.mar GarbageCollectedHeap.mar Args.mar DecimalToReal.mar Reals.mar RealDigits.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar"
files="elements.Text plain.Text lines.txt"
awk '{sub(/^MODULE texts;/, "MODULE TextsUse;"); sub(/^END texts\./, "END TextsUse."); gsub(/"texts"/, "\"TextsUse\""); print}' \
  ../llvm-texts/texts.mod >TextsUse.mod
: >result
# the files, as the host's build writes them
rm -rf host && mkdir host && cp TextsUse.mod host
(cd host && POC_IMPORT_PATH=../../../../rtl/llvm poc -o TextsUse -build TextsUse.mod >/dev/null 2>&1 && ./TextsUse >/dev/null)
echo "host build and run exit $?" >>result
{
  echo 'build status: %X10000001'
  sed -f vax-reals.sed ../llvm-texts/expected
  echo 'run status: %X00000001'
  echo 'plain.Text: an older version'
  for f in $files; do
    echo "== $f $(wc -c <host/$f | tr -d ' ')"
    od -An -v -tx1 host/$f | tr -d ' \n' | tr abcdef ABCDEF | fold -w 32; echo
  done
  echo 'run status: %X00000001'
} >texts.expected
rm -rf host
rm -f *.sym $written TextsUse.com FileBytes.com
for p in TextsUse FileBytes; do
  poc -target vax-dec-vms -import-path $rtl -build $p.mod >>result 2>&1
  echo "VAX build $p exit $?" >>result
done
vax_do guest-run.com texts.expected TextsUse.com FileBytes.com $written $rtl/PocRtl.mar
rm -f *.sym $written TextsUse.com FileBytes.com TextsUse.mod texts.expected
. ../../testresult.sh
