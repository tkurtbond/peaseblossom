#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 9): STR$'s
# decimal arithmetic through VMSLIB's DecimalStrings - add, subtract,
# multiply, divide, reciprocal and round, a signalled error returned as a
# status, and text to and from a Decimal - and through STR_ROUTINES
# itself, to show how STR$ fills a fixed-length result. The libraries
# POCRTL, VMSDEF (only the modules DecimalUse needs) and VMSLIB
# (DecimalStrings alone) are built, and DecimalUse against them. Where the
# VAX development system can be used, guest-run.com builds them there and
# runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="LIBDEF LIB_ROUTINES SSDEF STRDEF STR_ROUTINES"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  ../$vmslib/DecimalStrings.Mod) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp DecimalUse.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build DecimalUse.mod) >>result 2>&1
echo "VAX build DecimalUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/DecimalUse.mar work/DecimalUse.com
rm -rf work
. ../../testresult.sh
