#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1): what a
# ["VMS"] declaration and its calls accept, under -O2 and -OC, VmsServices'
# procedures through its .sym
: >result
rm -f VmsServices.sym VmsServices.mar
for model in -O2 -OC; do
  echo "== $model" >>result
  poc $model -target vax-dec-vms -emit-macro32 VmsServices.mod >>result 2>&1
  poc $model -check vms-arguments.mod >>result 2>&1
done
rm -f VmsServices.sym VmsServices.mar
. ../../testresult.sh
