#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 1 (doc/developer/vax-macro32-backend.md, section
# 18): poc -target vax-dec-vms -library makes a library for the VAX - the
# runtime's, POCRTL, from rtl/vax and PocRtl.mar, then VAXLIB, three
# dependent modules, which needs it - each in libs/vax-dec-vms/O2 with its
# modules' .sym and .mar, its manifest and its DCL procedures, VAXLIB's
# compared with expected-*; a program is compiled against them. Where the
# VAX development system can be used (../../vaxfixture.sh, vax_do), the
# procedures run there, and the program is linked and run against the
# shareable images and against the object libraries. Then what -library
# for the VAX refuses, each with exit status 1.
. ../../vaxfixture.sh
rm -rf libs main
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
compare() {
  if [ ! -f "$2" ]; then
    echo "$2 was not written" >>result
  elif diff "$1" "$2" >com-diff 2>&1; then
    echo "$2 matches $1" >>result
  else
    echo "$2 differs from $1:" >>result
    cat com-diff >>result
  fi
  rm -f com-diff
}
: >result
rtl=../../../rtl/vax
lib=libs/vax-dec-vms/O2
run -target vax-dec-vms -output-dir libs -library POCRTL $rtl/*.Mod $rtl/PocRtl.mar
run -target vax-dec-vms -output-dir libs -library-path libs -library VAXLIB VaxLibBase.mod VaxLibShapes.mod VaxLibSums.mod
compare expected-VAXLIB_build.com $lib/VAXLIB_build.com
compare expected-VAXLIB_setup.com $lib/VAXLIB_setup.com
grep -v '^poc ' $lib/VAXLIB.library >manifest
compare expected-VAXLIB.library manifest
rm -f manifest
grep -c '^UNIVERSAL=' $lib/POCRTL_build.com | sed 's/^/POCRTL symbols made universal: /' >>result
cmp -s $rtl/PocRtl.mar $lib/PocRtl.mar && echo "PocRtl.mar copied whole" >>result
(cd $lib && LC_ALL=C ls) | sed 's/^/in the library directory: /' >>result
mkdir main
run -target vax-dec-vms -library-path libs -output-dir main -emit-macro32 VaxLibUse.mod
vax_do guest-library.com guest-library.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com main/VaxLibUse.mar
run -target vax-dec-vms -library-path libs -library A234567890123456789012345678901234 VaxLibBase.mod
run -target vax-dec-vms -library-path libs -library BAD.NAME VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library NORTL VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library-path libs -library TWICE VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library-path libs -library PARTS VaxLibUse.mod vaxlibuse.mar
rm -rf libs2
. ../../testresult.sh
