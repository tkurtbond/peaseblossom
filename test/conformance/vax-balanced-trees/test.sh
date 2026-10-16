#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10):
# VMSLIB's BalancedTrees, a tree of the program's records made by NEW,
# kept through a collection, walked and searched; then LIB$INSERT_TREE
# and LIB$TRAVERSE_TREE through the program's own declarations. The
# libraries POCRTL, VMSDEF (only the modules TreeUse needs) and VMSLIB
# (BalancedTrees) are built, and TreeUse against them. Where the VAX
# development system can be used, guest-run.com builds them there and
# runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="LIBDEF SSDEF"
modules="BalancedTrees"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp TreeUse.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build TreeUse.mod) >>result 2>&1
echo "VAX build TreeUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/TreeUse.mar work/TreeUse.com
rm -rf work
. ../../testresult.sh
