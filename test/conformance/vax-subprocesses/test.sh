#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 11):
# VMSLIB's Subprocesses, run and started, waited for and stopped;
# LIB$SPAWN itself with a completion AST, with a process name twice and
# with one too long; and a chain, LIB$PUT_COMMON and LIB$RUN_PROGRAM from
# SpawnUse to ChainedUse, which ends by LIB$DO_COMMAND. The libraries POCRTL, VMSDEF
# (only the modules the two programs need) and VMSLIB (the modules
# SpawnUse uses) are built, and the two programs against them. Where the
# VAX development system can be used, guest-run.com builds them there
# and runs SpawnUse.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="CLIDEF LIBDEF LIB_ROUTINES LNMDEF SSDEF STARLET"
modules="EventFlags LogicalNames Subprocesses Symbols Timers"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp SpawnUse.mod ChainedUse.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build SpawnUse.mod) >>result 2>&1
echo "VAX build SpawnUse exit $?" >>result
(cd work && poc -target vax-dec-vms -library-path libs -build ChainedUse.mod) >>result 2>&1
echo "VAX build ChainedUse exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/SpawnUse.mar work/SpawnUse.com work/ChainedUse.mar work/ChainedUse.com
rm -rf work
. ../../testresult.sh
