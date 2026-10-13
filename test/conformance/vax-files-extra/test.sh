#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.3): rtl/vax's Files on VAX/VMS. For -O2 and -OC, FilesExtra built
# for the VAX and run there (vax_do, guest-run.com), which must print
# guest-run.expected: llvm-files' and llvm-files-extra's checks in VMS's
# names, with DCL where those use the shell, and section 19.3's own: Old
# leaves a revision date alone, two Files on one file, Purge, the search
# path, and the typed riders' reals at the edges of the ranges.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f FilesExtra.com
: >result
for model in -O2 -OC; do
  rm -f *.sym *.mar
  poc $model -target vax-dec-vms -import-path $rtl -build FilesExtra.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected FilesExtra.com FilesExtra.mar Files.mar Platform.mar \
    GarbageCollectedHeap.mar Out.mar LineOutput.mar $rtl/PocRtl.mar
done
rm -f *.sym *.mar FilesExtra.com
. ../../testresult.sh
