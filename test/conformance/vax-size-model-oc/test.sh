#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14): the VAX under -OC. poc -OC -emit-macro32's output for
# VaxSizeModel.mod, against the reviewed expected-vax.mar, assembled on the
# VAX where the development system can be used (../../vaxfixture.sh); then
# the program built with -OC -build and run there (vax_do), its exit status
# saying which of its checks held.
. ../../vaxfixture.sh
rm -f VaxSizeModel.com
: >result
vax_mar VaxSizeModel -OC
poc -OC -target vax-dec-vms -build VaxSizeModel.mod >>result 2>&1
echo "build exit $?" >>result
vax_do guest-run.com guest-run.expected VaxSizeModel.com VaxSizeModel.mar ../../../rtl/vax/PocRtl.mar
. ../../testresult.sh
