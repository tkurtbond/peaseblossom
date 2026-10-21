#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10): LIB$'s
# interlocked queue and bit routines through LIB_ROUTINES, with a
# queue's header and entries made by NEW. The libraries POCRTL and
# VMSDEF (only the modules QueueUse needs) are built, and QueueUse
# against them. Where the VAX development system can be used,
# guest-run.com builds them there and runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
rm -rf work
mkdir work
generated="LIBDEF LIB_ROUTINES SSDEF"
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
cp QueueUse.mod work/
(cd work && poc -target vax-dec-vms $vax_way_option -library-path libs -build QueueUse.mod) >>result 2>&1
echo "VAX build QueueUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*.obj $lib/*_build.com $lib/*_setup.com \
  work/QueueUse.mar work/QueueUse.com
}
vax_build builds
rm -rf work
. ../../testresult.sh
