#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
# 15, proposal 2): rtl/vax's Files. poc -emit-macro32's output for
# FilesUse.mod and rtl/vax/Files.Mod against the reviewed expected-vax.mar
# and expected-vax-Files.mar, assembled on the VAX where the development
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
  poc $model -target vax-dec-vms -import-path $rtl -build FilesOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected FilesOut.com FilesOut.mar Files.mar Out.mar LineOutput.mar \
    $rtl/PocRtl.mar
done
rm -f output
. ../../testresult.sh
