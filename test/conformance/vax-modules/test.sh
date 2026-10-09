#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 8: poc -emit-macro32's output for VaxModules.mod and
# its imports, VaxModLib.mod and VaxModBase.mod, against the reviewed
# expected-vax.mar and expected-vax-<Import>.mar, which are also assembled,
# linked and run on the VAX where the development system can be used
# (../../vaxfixture.sh)
. ../../vaxfixture.sh
: >result
vax_mar VaxModules
. ../../testresult.sh
