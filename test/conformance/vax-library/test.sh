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
# procedures run there, and the program both ways. -install-library
# copies each library, as text, into inst/vax-dec-vms/O2, the files the
# host has of it whole, over a copy installed before too, and -build
# finds them there. Then what -library and -install-library for the VAX
# refuse, each with exit status 1, and two exported names with one VAX
# symbol, when one or both modules come from a library, refused before
# anything is written. On the guest, also the failures a library's user
# can meet (proposal 8): its shareable image not found, the image
# relinked under a program linked against it before, and a program
# compiled against another interface of a module linked with the
# library, each stopped with VMS's message.
. ../../vaxfixture.sh
rm -rf libs main inst
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
# proposal 8's failure cases: the program compiled against a VAXLIB
# whose VaxLibSums has another interface, so another key (stale.com,
# renamed STALEUSE so that it can sit beside VAXLIBUSE on the guest)
mkdir stale stale-src
cp VaxLibBase.mod VaxLibShapes.mod stale-src/
sed 's/^  IMPORT VaxLibBase, VaxLibShapes;$/&\
  CONST changed* = 1;/' VaxLibSums.mod >stale-src/VaxLibSums.mod
run -target vax-dec-vms -output-dir stale -library-path libs -library VAXLIB \
  stale-src/VaxLibBase.mod stale-src/VaxLibShapes.mod stale-src/VaxLibSums.mod
run -target vax-dec-vms -library-path stale -library-path libs -output-dir stale -o stale -build VaxLibUse.mod
sed -e 's/^\$ MACRO\/OBJECT VAXLIBUSE\.MAR$/$ MACRO\/OBJECT STALEUSE.MAR/' -e 's/^VAXLIBUSE\.OBJ$/STALEUSE.OBJ/' \
  stale.com >stale-renamed.com && mv stale-renamed.com stale.com
cp stale/VaxLibUse.mar StaleUse.mar
cmp -s main/VaxLibUse.mar StaleUse.mar || echo "stale.com's program names another VaxLibSums key" >>result
vax_do guest-library.com guest-library.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  main/VaxLibUse.mar useolb.com useshr.com StaleUse.mar stale.com
rm -rf stale stale-src StaleUse.mar stale.com
run -target vax-dec-vms -library-path libs -output-dir inst -install-library POCRTL
run -target vax-dec-vms -library-path libs -output-dir inst -install-library VAXLIB
run -target vax-dec-vms -library-path libs -output-dir inst -install-library VAXLIB
for f in $lib/*; do
  cmp -s $f inst/vax-dec-vms/O2/${f##*/} || echo "${f##*/} is not installed whole" >>result
done
(cd $lib && LC_ALL=C ls) >files.libs; (cd inst/vax-dec-vms/O2 && LC_ALL=C ls) >files.inst
cmp -s files.libs files.inst && echo "inst/vax-dec-vms/O2 has the files of $lib" >>result
rm -f files.libs files.inst
mkdir main2
run -target vax-dec-vms -library-path inst -output-dir main2 -o useinst -build VaxLibUse.mod
sed 's/USEINST/USEOLB/g' useinst.com >useinst-renamed.com
compare useolb.com useinst-renamed.com
rm -rf main2 useinst.com useinst-renamed.com
run -target vax-dec-vms -library-path libs -output-dir libs -install-library VAXLIB
run -target vax-dec-vms -library-path libs -output-dir inst -install-library NONE
run -target vax-dec-vms -library-path libs -output-dir inst2 -install-library POCRTL
run -target vax-dec-vms -library-path inst2 -output-dir libs3 -library OTHER VaxLibBase.mod
run -target vax-dec-vms -library-path libs3 -library-path inst2 -output-dir inst2 -install-library OTHER
run -target vax-dec-vms -library-path libs -output-dir inst2 -install-library VAXLIB
rm -rf inst2 libs3
run -target vax-dec-vms -library-path libs -library A234567890123456789012345678901234 VaxLibBase.mod
run -target vax-dec-vms -library-path libs -library BAD.NAME VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library NORTL VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library-path libs -library TWICE VaxLibBase.mod
run -target vax-dec-vms -output-dir libs2 -library-path libs -library PARTS VaxLibUse.mod vaxlibuse.mar
rm -rf libs2
# Phase 17 step 1 (section 18, proposal 7): two names with one VAX symbol
# in one program, vax-build's pair (copied here, with the names that give
# it), one or both taken from a library
run -target vax-dec-vms -output-dir libs3 -library-path libs -library CLASHA VaxClashBetweenModulesA.mod
mkdir clash1
run -target vax-dec-vms -library-path libs3 -library-path libs -output-dir clash1 -build VaxBuildClash.mod
run -target vax-dec-vms -output-dir libs4 -library-path libs3 -library-path libs -library CLASHUSE \
  VaxClashBetweenModulesB.mod VaxBuildClash.mod
run -target vax-dec-vms -output-dir libs3 -library-path libs -library CLASHB VaxClashBetweenModulesB.mod
mkdir clash2
run -target vax-dec-vms -library-path libs3 -library-path libs -output-dir clash2 -build VaxBuildClash.mod
ls clash2/*.mar 2>/dev/null | sed 's/^/written: /' >>result
rm -rf libs3 libs4 clash1 clash2
rm -f VaxBuildClash.sym VaxClashBetweenModulesB.sym
rm -f VaxBuildClash.com
. ../../testresult.sh
