#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4, proposal
# 6): the hand-written modules of rtl/vax/vmslib, Conditions, LogicalNames
# and Symbols, and step 6's EventFlags, ExitHandlers and Timers, which
# vax-asts and vax-conditions-handlers run. Each compiles for the VAX under -O2 and -OC; they make the
# library VMSLIB, which needs POCRTL and VMSDEF. Here VMSDEF holds only
# the generated modules VMSLIB and the programs import, not all of
# rtl/vax/vms, which vax-vmsdef builds. Where the VAX development system
# can be used, guest-run.com builds the three libraries there and runs
# programs linked against them, with the logical names and symbols they
# expect, and shows what each leaves. Part 5: Conditions.SignalList and
# StopList, through LIB$CALLG (VmsLibSignal, VmsLibStopList), and a list
# too long for CALLG (VmsLibListTooLong). CommandLanguage, SortMerge
# (part 8), DecimalStrings (part 9), and BalancedTrees and DateTimes (part
# 10) and Subprocesses (part 11) compile here; vax-cli-verb and
# vax-cli-table run CommandLanguage, vax-sort SortMerge,
# vax-decimal-strings DecimalStrings, vax-balanced-trees BalancedTrees,
# vax-date-times DateTimes, and vax-subprocesses Subprocesses.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
rm -rf work
mkdir work work/o2 work/oc
generated="CLIDEF CLIMSGDEF LIBDEF LIB_ROUTINES LNMDEF RMSDEF SSDEF STARLET STR_ROUTINES"
modules="BalancedTrees CommandLanguage Conditions DateTimes DecimalStrings EventFlags ExitHandlers LogicalNames SortMerge Subprocesses Symbols Timers"
for model in O2 OC; do
  dir=work/$(echo $model | tr A-Z a-z)
  for m in $modules; do
    poc -$model -target vax-dec-vms -import-path $vms -import-path $rtl -import-path $vmslib -output-dir $dir \
      -emit-macro32 $vmslib/$m.Mod >$dir/out 2>&1 || cat $dir/out >>result
  done
  echo "-$model: compiled" >>result
done
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >work/out 2>&1 || cat work/out >>result
(cd work && poc -target vax-dec-vms $vax_way_option -output-dir libs -library-path libs -library VMSLIB \
  $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >>result 2>&1
echo "VMSLIB exit $?" >>result
programs="VmsLibConditions VmsLibLogicals VmsLibSymbols VmsLibSignal VmsLibStopWith VmsLibStopList VmsLibListTooLong"
for p in $programs; do
  cp $p.mod work/
  (cd work && poc -target vax-dec-vms $vax_way_option -library-path libs -o $p -build $p.mod) >>result 2>&1
  echo "VAX build $p exit $?" >>result
done
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*.obj $lib/*_build.com $lib/*_setup.com \
  $(for p in $programs; do echo work/$p.mar work/$p.com; done)
}
vax_build builds
rm -rf work
. ../../testresult.sh
