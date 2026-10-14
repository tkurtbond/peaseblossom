#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1, proposal
# 8): poc -emit-macro32's output for VaxVmsArguments.mod, each way a
# ["VMS"] declaration passes an argument, and for rtl/vax/VmsArguments.Mod,
# which it imports, against the reviewed expected-vax.mar and
# expected-vax-VmsArguments.mar, assembled on the VAX where the
# development system can be used (../../vaxfixture.sh). vax-vms-calls runs
# real routines called these ways.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
: >result
rm -f *.sym
vax_mar VaxVmsArguments -import-path $rtl
rm -f *.sym VaxVmsArguments.mar VmsArguments.mar
. ../../testresult.sh
