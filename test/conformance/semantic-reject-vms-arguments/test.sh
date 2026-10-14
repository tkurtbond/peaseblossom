#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1): what a
# ["VMS"] declaration and its calls refuse, under -O2 and -OC (where a
# LONGINT value parameter is a quadword); NIL omits an argument of a
# ["VMS"] procedure only, not a ["C"] one
: >result
for model in -O2 -OC; do
  echo "== $model" >>result
  poc $model -check vms-arguments.mod >>result 2>&1
done
. ../../testresult.sh
