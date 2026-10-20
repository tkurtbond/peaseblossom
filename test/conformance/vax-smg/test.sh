#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 7): SMG$
# screen management through the generated declarations alone (SMG_ROUTINES,
# SMGDEF, SMGMSG, SSDEF), with no module over them: SmgFile draws on a
# pasteboard on a file, captures it with SMG$SNAPSHOT, and reads a
# keyboard on a file. The libraries POCRTL and VMSDEF (only the modules
# SmgFile imports) are built, and SmgFile against them. Where the VAX
# development system can be used, guest-run.com builds them there and runs
# it. SmgScreen, the same on a terminal, is run by hand (part 7, proposal
# 4); it is only compiled here.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
rtl=../../../rtl/vax
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
rm -rf work
mkdir work
generated="SMGDEF SMGMSG SMG_ROUTINES SSDEF"
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
cp SmgFile.mod SmgScreen.mod work/
(cd work && poc -target vax-dec-vms $vax_way_option -library-path libs -build SmgFile.mod) >>result 2>&1
echo "VAX build SmgFile exit $?" >>result
(cd work && poc -target vax-dec-vms $vax_way_option -library-path libs -build SmgScreen.mod) >>result 2>&1
echo "VAX build SmgScreen exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*.obj $lib/*_build.com $lib/*_setup.com \
  work/SmgFile.mar work/SmgFile.com
}
vax_build builds
rm -rf work
. ../../testresult.sh
