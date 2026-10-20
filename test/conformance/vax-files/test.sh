#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
# 15, proposal 2; section 19.3, Phase 17 step 3): rtl/vax's Files. poc
# -emit-macro32's output for FilesUse.mod and rtl/vax/Files.Mod, and the
# modules Files imports, against the reviewed expected-vax.mar and
# expected-vax-<Module>.mar, assembled on the VAX where the development
# system can be used (../../vaxfixture.sh). Then, for -O2 and -OC,
# FilesOut built by the LLVM backend and run here, with FILESVAR.TXT and
# FILESVFC.TXT plain text, which must print output.expected, and built for
# the VAX and run there (vax_do, guest-run.com), with them made
# variable-length and VFC, which must print guest-run.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
made="FILESOUT.TXT FILESOUT.BIN FILESOUT.STR FILESOUT.EMP FILESVAR.TXT FILESVFC.TXT"
rm -f FilesOut.com $made
: >result
vax_mar FilesUse -import-path $rtl
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-files -build FilesOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  printf 'a variable-length source\n\n  indented, after an empty record\n' >FILESVAR.TXT
  printf "a VFC source, as DCL's OPEN/WRITE makes\n\n  its last record\n" >FILESVFC.TXT
  ./vax-files >output 2>&1
  echo "status: $?" >>output
  rm -f $made
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms $vax_way_option -import-path $rtl -build FilesOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected FilesOut.com FilesOut.mar Files.mar Platform.mar GarbageCollectedHeap.mar \
    Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar $rtl/PocRtl.mar
done
}
vax_build builds
rm -f output *.obj
. ../../testresult.sh
