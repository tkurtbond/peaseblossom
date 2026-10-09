#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 1): open arrays on the VAX. poc -emit-macro32's output for
# VaxOpenArrays.mod, against the reviewed expected-vax.mar, assembled and
# run under the debugger on the VAX where the development system can be
# used (../../vaxfixture.sh); then the program built with -build, under -O2
# and then -OC, and run there (vax_do), its exit status saying which of its
# checks held.
. ../../vaxfixture.sh
rm -f VaxOpenArrays.com
: >result
vax_mar VaxOpenArrays
for model in -O2 -OC; do
  poc $model -target vax-dec-vms -build VaxOpenArrays.mod >>result 2>&1
  echo "build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected VaxOpenArrays.com VaxOpenArrays.mar ../../../rtl/vax/PocRtl.mar
done
. ../../testresult.sh
