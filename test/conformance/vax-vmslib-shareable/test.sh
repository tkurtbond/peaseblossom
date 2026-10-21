#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 8 (the plan's second gap): every module of
# rtl/vax/vmslib used from one program, ShareUse, built four ways: under
# -O2 and -OC, each linked with the object libraries (-o shareolb) and
# with the shareable images (-shared-libraries, -o shareshr). A shareable
# image has its own copy of its writable data, so what this checks most is
# the state VMSLIB keeps there, ExitHandlers' blocks and Subprocesses'
# list, which must stay reachable for the collector from POCRTL's image.
# Where the VAX development system can be used, guest-run.com builds
# POCRTL, VMSDEF (only the generated modules VMSLIB imports) and VMSLIB
# there, then both programs, and runs them; once per size model, since the
# two models' library files have the same names, and each of the four runs
# prints guest-run.expected's lines.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
: >result
# Built and run both ways, from MACRO-32 and from poc's objects (vax_build).
builds() {
rm -rf work
mkdir work
generated="CLIDEF CLIMSGDEF LIBDEF LIB_ROUTINES LNMDEF RMSDEF SSDEF STARLET STR_ROUTINES"
modules="BalancedTrees CommandLanguage Conditions DateTimes DecimalStrings EventFlags ExitHandlers LogicalNames SortMerge Subprocesses Symbols Timers"
cp ShareUse.mod work/
for model in O2 OC; do
  (cd work && poc -$model -target vax-dec-vms $vax_way_option -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) \
    ../$rtl/PocRtl.mar) >work/out 2>&1 || cat work/out >>result
  (cd work && poc -$model -target vax-dec-vms $vax_way_option -output-dir libs -library-path libs -library VMSDEF \
    $(for m in $generated; do echo ../$vms/$m.Mod; done)) >work/out 2>&1 || cat work/out >>result
  (cd work && poc -$model -target vax-dec-vms $vax_way_option -output-dir libs -library-path libs -library VMSLIB \
    $(for m in $modules; do echo ../$vmslib/$m.Mod; done)) >work/out 2>&1 || cat work/out >>result
  for linkage in olb shr; do
    case $linkage in shr) shared=-shared-libraries ;; *) shared= ;; esac
    (cd work && poc -$model -target vax-dec-vms $vax_way_option -library-path libs $shared -output-dir $model -o share$linkage \
      -build ShareUse.mod) >work/out 2>&1 || cat work/out >>result
    echo "-$model share$linkage: built" >>result
  done
  lib=work/libs/vax-dec-vms/$model
  vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*.obj $lib/*_build.com $lib/*_setup.com \
    work/$model/ShareUse.mar work/shareolb.com work/shareshr.com
done
}
vax_build builds
rm -rf work
. ../../testresult.sh
