#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vax-macro32-backend.md, section 23,
# proposal 8): CommandLanguage with a program's own command table,
# CliCommands.cld, which poc -build compiles and links (proposal 5). The
# libraries POCRTL, VMSDEF (only the generated modules VMSLIB and the
# program import) and VMSLIB are built, and CliTable against them. Where
# the VAX development system can be used, guest-run.com builds them there
# and runs CliTable: its own lines, then lines read at a prompt, then as a
# foreign command.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="CLIMSGDEF IODEF LIBDEF LIB_ROUTINES LNMDEF RMSDEF SSDEF STARLET"
modules="CommandLanguage Conditions EventFlags ExitHandlers LogicalNames Symbols Timers"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >work/out 2>&1 || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp CliTable.mod CliCommands.cld work/
(cd work && poc -target vax-dec-vms -library-path libs -build CliTable.mod CliCommands.cld) >>result 2>&1
echo "VAX build CliTable exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/CliTable.mar work/CliTable.com work/CliCommands.cld
rm -rf work
. ../../testresult.sh
