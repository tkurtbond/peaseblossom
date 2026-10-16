#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 12): the
# synchronous system services of the supported tier through STARLET -
# $GETSYIW, $GETDVIW, a mailbox ($CREMBX, $QIOW, $DASSGN), $NUMTIM, $FAO
# and $FAOL, $ENQW and $DEQ with VmsArguments.LockStatusBlock, $WAKE and
# $HIBER, $SETPRN. The libraries POCRTL, VMSDEF (only the modules
# ServiceUse needs) and VMSLIB (EventFlags and Timers) are built, and
# ServiceUse against them. Where the VAX development system can be used,
# guest-run.com builds them there and runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="CLIDEF DCDEF DVIDEF IODEF JPIDEF LCKDEF LIBDEF LIB_ROUTINES SSDEF STARLET SYIDEF"
modules="EventFlags Timers"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp ServiceUse.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build ServiceUse.mod) >>result 2>&1
echo "VAX build ServiceUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/ServiceUse.mar work/ServiceUse.com
rm -rf work
. ../../testresult.sh
