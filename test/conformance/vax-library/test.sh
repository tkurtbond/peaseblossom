#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 1 (doc/developer/vax-macro32-backend.md, section
# 18): poc -target vax-dec-vms -library makes a library for the VAX - the
# runtime's, POCRTL, from rtl/vax and PocRtl.mar, then VAXLIB, three
# dependent modules, which needs it - each in libs/vax-dec-vms/O2 with its
# modules' .sym and .mar, its manifest and its DCL procedures, VAXLIB's
# compared with expected-*; a program is built against them with -build,
# whose procedures link it with their object libraries (useolb.com) or,
# with -shared-libraries, their shareable images (useshr.com). Where the
# VAX development system can be used (../../vaxfixture.sh, vax_do), the
# procedures run there, and the program both ways. Then what -library
# for the VAX refuses, each with exit status 1.
. ../../vaxfixture.sh
rm -rf libs main
rm -f useolb.com useshr.com
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
run -target vax-dec-vms -library-path libs -output-dir main -o useolb -build VaxLibUse.mod
compare expected-useolb.com useolb.com
run -target vax-dec-vms -library-path libs -shared-libraries -output-dir main -o useshr -build VaxLibUse.mod
compare expected-useshr.com useshr.com
vax_do guest-library.com guest-library.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  main/VaxLibUse.mar useolb.com useshr.com
run -target vax-dec-vms -library-path libs -library A234567890123456789012345678901234 VaxLibBase.mod
run -target vax-dec-vms -library-path libs -library BAD.NAME VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library NORTL VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library-path libs -library TWICE VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library-path libs -library PARTS VaxLibUse.mod vaxlibuse.mar
rm -rf libs2
. ../../testresult.sh
