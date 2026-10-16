#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10):
# VMSLIB's DateTimes on fixed times: text in and out, sums and
# differences, deltas from units, a time's parts, and
# LIB$FORMAT_DATE_TIME. The libraries POCRTL, VMSDEF (only the modules
# DateUse needs) and VMSLIB (DateTimes) are built, and DateUse against
# them. Where the VAX development system can be used, guest-run.com
# builds them there and runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="LIBDEF LIBDTDEF LIB_ROUTINES SSDEF STARLET"
modules="DateTimes"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp DateUse.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build DateUse.mod) >>result 2>&1
echo "VAX build DateUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/DateUse.mar work/DateUse.com
rm -rf work
. ../../testresult.sh
