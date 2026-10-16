#!/bin/sh
. ../../testenv.sh
# PLAN.md, "Ongoing language enhancements", item 3: poc -emit-macro32's
# output for VaxExternalAddress.mod, against the reviewed expected-vax.mar,
# which is also assembled on the VAX where the development system can be
# used (../../vaxfixture.sh)
. ../../vaxfixture.sh
: >result
vax_mar VaxExternalAddress
. ../../testresult.sh
