#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 6: poc -emit-macro32's output for VaxStrings.mod, against
# the reviewed expected-vax.mar, which is also assembled on the VAX where the
# development system can be used (../../vaxfixture.sh)
. ../../vaxfixture.sh
: >result
vax_mar VaxStrings
. ../../testresult.sh
