#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 2, proposal
# 8): the modules tools/sdloberon generated from STARLETSD.TLB, in
# rtl/vax/vms. Each compiles for the VAX under -O2 and -OC; together they
# make the library VMSDEF. Where the VAX development system can be used:
# - every constant of each $xxxDEF module is compared with what SDL's
#   MACRO back end defines in STARLET.MLB, the macro $xxxDEF GLOBAL's
#   listing, by compare-mlb.awk, against expected-mlb;
# - POCRTL and VMSDEF are built there, and two programs against them
#   (guest-run.com): VmsDefLayout, which layout-check.awk writes, checks
#   poc's layout of every record type against SDL's offsets and sizes;
#   VmsDefCalls calls real routines through the generated declarations.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
rtl=../../../rtl/vax
tools=../../../tools
rm -rf work
mkdir work work/o2 work/oc
: >result
modules=$(cd $vms && LC_ALL=C ls *.Mod)
for model in O2 OC; do
  dir=work/$(echo $model | tr A-Z a-z)
  count=0
  for m in $modules; do
    if poc -$model -target vax-dec-vms -output-dir $dir -emit-macro32 $vms/$m >$dir/out 2>&1; then
      count=$((count + 1))
    else
      cat $dir/out >>result
    fi
  done
  echo "-$model: $count modules compiled" >>result
done
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF $(for m in $modules; do echo ../$vms/$m; done)) \
  >>result 2>&1
echo "VMSDEF exit $?" >>result
lib=work/libs/vax-dec-vms/O2
grep -c '^\$ MACRO/OBJECT' $lib/VMSDEF_build.com | sed 's/^/VMSDEF modules assembled: /' >>result
awk -f layout-check.awk $(for m in $modules; do echo $vms/$m; done) >work/VmsDefLayout.mod
cp VmsDefCalls.mod work/
for p in VmsDefLayout VmsDefCalls; do
  (cd work && poc -target vax-dec-vms -library-path libs -o $p -build $p.mod) >>result 2>&1
  echo "VAX build $p exit $?" >>result
done

# the $xxxDEF modules against STARLET.MLB
if [ "${VAX_GUEST:-}" = skip ]; then
  echo "SKIPPED: comparing with STARLET.MLB on the VAX (VAX_GUEST=skip)"
elif "$tools/vax-assemble" -available; then
  mkdir work/mlb
  gets= files=
  for m in $modules; do
    case $m in *DEF.Mod) ;; *) continue ;; esac
    n=${m%.Mod}
    printf '\t.TITLE\tC_%s\n\t$%s GLOBAL\n\t.END\n' "$n" "$n" >work/mlb/C_$n.MAR
    gets="$gets -get C_$n.LIS" files="$files work/mlb/C_$n.MAR"
  done
  # shellcheck disable=SC2086
  if "$tools/vax-do" -o work/mlb $gets mlb-listings.com $files >work/mlb/out 2>&1; then
    for m in $modules; do
      case $m in *DEF.Mod) ;; *) continue ;; esac
      awk -f compare-mlb.awk $vms/$m work/mlb/C_${m%.Mod}.LIS
    done >work/mlb-compared
    diff expected-mlb work/mlb-compared >work/mlb-diff 2>&1 \
      || { echo "the constants differ from expected-mlb:" >>result; cat work/mlb-diff >>result; }
  else
    echo "mlb-listings.com failed on the VAX:" >>result
    cat work/mlb/out >>result
  fi
else
  echo "SKIPPED: comparing with STARLET.MLB (no VAX development system here)"
fi

# the libraries built on the VAX, and the programs against them
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/VmsDefLayout.mar work/VmsDefLayout.com work/VmsDefCalls.mar work/VmsDefCalls.com
rm -rf work
. ../../testresult.sh
