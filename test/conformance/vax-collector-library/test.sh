#!/bin/sh
. ../../testenv.sh
# A VAX program whose main module calls no NEW, built against a library
# whose module does (BUGS.md, 2026-10-28): its start must still set up
# GarbageCollectedHeap and give it the stack's base, or a collection does
# not mark from the stack. POCRTL and HOLDLIB are built from poc's objects
# (-vax-objects), then HoldUse against them: its MAIN_MAIN, from
# -emit-macro32 and from -build, must call GARBAGECOLLECTEDHEAP_INIT and
# SetStackBase. HOLDLIB's manifest says HoldLib allocates and PlainLib,
# which calls no NEW, does not, and PlainUse, which uses only PlainLib,
# gets no setup (PLAN.md, "Ongoing bug fixing", 11). Where the VAX development system can be used
# (../../vaxfixture.sh), the libraries are built there and the program
# linked against them and run (guest-run.com): the things it holds only
# in a local must survive the collections HoldLib.Churn forces.
. ../../vaxfixture.sh
rm -rf libs main emit
rm -f HoldUse.com
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
start() {
  echo "$1's start:" >>result
  sed -n "/\\.ENTRY	${2:-HOLDUSE}_MAIN/,/RET/p" "$1" >>result
}
: >result
rtl=../../../rtl/vax
lib=libs/vax-dec-vms/O2
echo "== poc -target vax-dec-vms -vax-objects -output-dir libs -library POCRTL rtl/vax/*.Mod rtl/vax/PocRtl.mar" >>result
poc -target vax-dec-vms -vax-objects -output-dir libs -library POCRTL $(LC_ALL=C ls $rtl/*.Mod) $rtl/PocRtl.mar >>result 2>&1
echo "exit $?" >>result
run -target vax-dec-vms -vax-objects -output-dir libs -library-path libs -library HOLDLIB HoldLib.mod PlainLib.mod
echo "HOLDLIB's modules:" >>result
grep '^module ' $lib/HOLDLIB.library | sed 's/ [0-9a-f]* / <key> /' >>result
mkdir emit main
poc -target vax-dec-vms -library-path libs -output-dir emit -emit-macro32 HoldUse.mod >/dev/null 2>&1
start emit/HoldUse.mar
poc -target vax-dec-vms -library-path libs -output-dir emit -emit-macro32 PlainUse.mod >/dev/null 2>&1
start emit/PlainUse.mar PLAINUSE
run -target vax-dec-vms -library-path libs -output-dir main -o HoldUse -build HoldUse.mod
start main/HoldUse.mar
run -target vax-dec-vms -vax-objects -library-path libs -output-dir main -o HoldUse -build HoldUse.mod
vax_do guest-run.com guest-run.expected $lib/*.obj $lib/PocRtl.mar $lib/*_build.com $lib/*_setup.com \
  main/HoldUse.obj HoldUse.com
rm -rf libs main emit
rm -f HoldUse.com HoldUse.sym HoldLib.sym PlainUse.sym PlainLib.sym
. ../../testresult.sh
