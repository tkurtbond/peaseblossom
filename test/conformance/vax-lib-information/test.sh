#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10):
# LIB$GETJPI, LIB$GETSYI, LIB$GETDVI and LIB$GETQUI through
# LIB_ROUTINES, one item at a time, and their errors. The libraries
# POCRTL and VMSDEF (only the modules InfoUse needs) are built, and
# InfoUse against them. Where the VAX development system can be used,
# guest-run.com builds them there and runs it.
. ../../vaxfixture.sh
# what the guest prints names POC's account (its user name or home), so
# this runs under POC's alone, not POC2's (tools/vax-lock.sh)
VAX_USER=poc; export VAX_USER
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="DCDEF DVIDEF JBCMSGDEF JPIDEF LIBDEF LIB_ROUTINES QUIDEF SSDEF SYIDEF"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
cp InfoUse.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build InfoUse.mod) >>result 2>&1
echo "VAX build InfoUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/InfoUse.mar work/InfoUse.com
rm -rf work
. ../../testresult.sh
