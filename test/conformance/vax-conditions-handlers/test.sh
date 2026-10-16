#!/bin/sh
. ../../testenv.sh
# Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
# proposals 5 and 8): condition handlers by Conditions.Establish - one
# that continues, one that resignals, Unwind, an access violation caught,
# Revert (Handlers) - and exit handlers by ExitHandlers.Declare, their
# order and the status they leave (ExitStatus). Built as vax-asts' are,
# and run where the VAX development system can be used (guest-run.com).
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="CLIMSGDEF IODEF LIBDEF LIB_ROUTINES LNMDEF RMSDEF SSDEF STARLET STR_ROUTINES"
modules=$(cd $vmslib && LC_ALL=C ls *.Mod)
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >work/out 2>&1 || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
programs="Handlers ExitStatus"
for p in $programs; do
  cp $p.mod work/
  (cd work && poc -target vax-dec-vms -library-path libs -o $p -build $p.mod) >>result 2>&1
  echo "VAX build $p exit $?" >>result
done
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  $(for p in $programs; do echo work/$p.mar work/$p.com; done)
rm -rf work
. ../../testresult.sh
