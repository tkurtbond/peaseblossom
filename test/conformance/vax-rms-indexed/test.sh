#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 6): RMS's
# indexed and relative files, keyed access, $FIND, $UPDATE, $DELETE and
# record locking, through the generated declarations alone (STARLET,
# FABDEF, RABDEF, XABDEF, XABKEYDEF, RMSDEF), with no module over them.
# The libraries POCRTL and VMSDEF (only the modules RmsIndexed imports)
# are built, and RmsIndexed against them. Where the VAX development system
# can be used, guest-run.com builds them there and runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="FABDEF RABDEF RMSDEF STARLET XABDEF XABKEYDEF"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
cp RmsIndexed.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build RmsIndexed.mod) >>result 2>&1
echo "VAX build RmsIndexed exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/RmsIndexed.mar work/RmsIndexed.com
rm -rf work
. ../../testresult.sh
