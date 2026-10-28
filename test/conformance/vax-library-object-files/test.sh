#!/bin/sh
. ../../testenv.sh
# doc/developer/vax-macro32-backend.md, section 13.1, proposal 6: poc
# -target vax-dec-vms -library takes object files, .obj files in any case
# after its modules and parts, each in the counted form, as -build does
# (vax-build-object-files). The library EXT, from ExtLib.mod, the part
# Thrice.mar (hand-Thrice.mar) and two objects - Helper's, which poc writes here, and
# Every.obj, made here byte by byte, a GSD subrecord of each of the object
# language's types - in libs/vax-dec-vms/O2: each object copied beside
# the modules, inserted in EXT.OLB and listed in EXT.OPT after the part,
# its entry points (EPM, PRO, EPMW and PROW; not the local ones, nor any
# symbol) made UNIVERSAL=, and an "object" line in the manifest; the
# procedure is compared with expected-EXT_build.com, and with
# expected-EXT_build-objects.com when the modules are poc's objects
# (-vax-objects), the manifest with expected-EXT.library. -install-library
# copies the objects whole, and drops them when a library made again has
# none. Then what is refused, each with exit status 1 and no library
# directory made: an object whose name is a module's, a part's object's,
# another object's or the runtime's, a name VMS cannot have, an object that
# is not there or not in the counted form, and one whose GSD records cannot
# be read (a subrecord of no type the object language has, and one that
# runs past its record). Where the VAX development system can be used
# (../../vaxfixture.sh), hand-Twice.mar is assembled there and brought back
# in the counted form (guest-counted.com); EXT is made again with it in
# place of the two objects, and POCRTL and EXT built from poc's objects
# there, and ExtUse, which calls ExtLib, TWICE and THRICE, built against
# their shareable images and their object libraries, and run
# (guest-library.com, guest-library.expected).
. ../../vaxfixture.sh
rm -rf work
mkdir work work/other
run() {
  echo "== poc $*" >>result
  (cd work && poc "$@") >>result 2>&1
  echo "exit $?" >>result
}
# poc on the guest's part, which adds to result only if it fails
quiet() {
  if ! (cd work && poc "$@") >work/out 2>&1; then
    echo "poc $* failed:" >>result; cat work/out >>result
  fi
}
compare() {
  if [ ! -f "work/$2" ]; then
    echo "$2 was not written" >>result
  elif diff "$1" "work/$2" >work/diff 2>&1; then
    echo "$2 matches $1" >>result
  else
    echo "$2 differs from $1:" >>result; cat work/diff >>result
  fi
}
# the object file Every.obj: an MHD record, then two GSD records
every_object() {
  printf '\007\000' # a record of 7 bytes
  printf '\000\001\004\110\101\116\104' # MHD, skipped
  printf '\000' # the pad
  printf '\200\000' # a record of 128 bytes
  printf '\001' # GSD
  printf '\000\002\002\000\000\000\000\000\005\044\103\117\104\105' # PSC $CODE
  printf '\001\000\000\000\006\123\131\115\122\105\106' # SYM SYMREF, a reference
  printf '\001\000\002\000\000\000\000\000\000\006\123\131\115\104\105\106' # SYM SYMDEF, a definition
  printf '\002\000\002\000\000\000\000\000\000\000\000\007\105\116\124\122\131\137\101' # EPM ENTRY_A
  printf '\003\000\002\000\000\000\000\000\000\000\000\006\120\122\117\103\137\102\001\002\000\000\000\002\005\006' # PRO PROC_B, two arguments, the second with two bytes
  printf '\005\000\002\000\000\000\000\000\000\000\000\000\007\105\116\124\122\131\137\103' # EPMW ENTRY_C
  printf '\006\000\002\000\000\000\000\000\000\000\000\000\006\120\122\117\103\137\104\000\000' # PROW PROC_D, no arguments
  printf '\202\000' # a record of 130 bytes
  printf '\001' # GSD
  printf '\012\000\002\000\000\000\000\000\000\000\000\000\000\000\007\114\117\103\101\114\137\105' # LEPM LOCAL_E
  printf '\013\000\002\000\000\000\000\000\000\000\000\000\000\000\007\114\117\103\101\114\137\106\000\000' # LPRO LOCAL_F
  printf '\007\000\000\003\105\116\124\002\126\061\003\117\102\112' # IDC
  printf '\010\000\000\000\000\007\105\116\126\116\101\115\105' # ENV
  printf '\011\000\002\000\000\000\000\000\000\000\000\000\006\114\123\131\104\105\106' # LSY LSYDEF, a definition
  printf '\004\000\002\000\000\000\000\000\000\000\007\123\131\115\127\104\105\106' # SYMW SYMWDEF, a definition
  printf '\014\002\000\000\000\000\000\000\000\000\000\000\006\123\110\101\122\105\104' # SPSC SHARED
  printf '\000\000' # the end
}
: >result
rtl=../../../../rtl/vax
lib=libs/vax-dec-vms/O2
cp ExtLib.mod ExtUse.mod Helper.mod work/
cp hand-Thrice.mar work/Thrice.mar
(cd work && poc -target vax-dec-vms -emit-vax-object Helper.mod) >>result 2>&1
mv work/Helper.obj work/other/Helper.obj
every_object >work/Every.obj
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls $rtl/*.Mod) $rtl/PocRtl.mar) >>result 2>&1
echo "POCRTL exit $?" >>result
(cd work && poc -target vax-dec-vms -vax-objects -output-dir olibs -library POCRTL $(LC_ALL=C ls $rtl/*.Mod) $rtl/PocRtl.mar) >>result 2>&1
echo "POCRTL from objects exit $?" >>result
run -target vax-dec-vms -output-dir libs -library-path libs -library EXT ExtLib.mod Thrice.mar other/Helper.obj Every.obj
compare expected-EXT_build.com $lib/EXT_build.com
grep -v '^poc ' work/$lib/EXT.library >work/manifest
compare expected-EXT.library manifest
cmp -s work/other/Helper.obj work/$lib/Helper.obj && echo "other/Helper.obj copied to Helper.obj" >>result
cmp -s work/Every.obj work/$lib/Every.obj && echo "Every.obj copied whole" >>result
(cd work/$lib && LC_ALL=C ls) | grep -E '^(Ext|EXT|Helper|Every|Thrice)' | sed 's/^/in the library directory: /' >>result
run -target vax-dec-vms -vax-objects -output-dir oext -library-path olibs -library EXT ExtLib.mod Thrice.mar \
  other/Helper.obj Every.obj
compare expected-EXT_build-objects.com oext/vax-dec-vms/O2/EXT_build.com
run -target vax-dec-vms -library-path libs -output-dir inst -install-library EXT
run -target vax-dec-vms -library-path libs -output-dir inst -install-library EXT
for f in Helper.obj Every.obj; do
  cmp -s work/$lib/$f work/inst/vax-dec-vms/O2/$f && echo "$f installed whole" >>result
done
run -target vax-dec-vms -output-dir libs -library-path libs -library EXT ExtLib.mod Thrice.mar
run -target vax-dec-vms -library-path libs -output-dir inst -install-library EXT
for f in Helper.obj Every.obj; do
  [ -f work/inst/vax-dec-vms/O2/$f ] && echo "$f still installed" >>result
done
rm -rf work/inst
cp work/other/Helper.obj work/ExtLib.obj
cp work/other/Helper.obj work/Thrice.obj
cp work/other/Helper.obj work/other/HELPER.OBJ
cp work/other/Helper.obj work/POCRTL.obj
cp work/other/Helper.obj work/bad.name.obj
printf 'not an object\n' >work/Text.obj
tail -c +3 work/other/Helper.obj >work/Ftp.obj
printf '\003\000\001\143\000\000\000\000' >work/BadType.obj
printf '\020\000\001\002\000\002\000\000\000\000\000\000\000\000\011\105\116\124\000\000' >work/Short.obj
for objects in ExtLib.obj Thrice.obj "other/Helper.obj other/HELPER.OBJ" POCRTL.obj bad.name.obj missing.obj \
    Text.obj Ftp.obj BadType.obj Short.obj; do
  run -target vax-dec-vms -output-dir refused -library-path libs -library EXT ExtLib.mod Thrice.mar $objects
  [ -d work/refused/vax-dec-vms/O2 ] && echo "refused/vax-dec-vms/O2 made" >>result
  rm -rf work/refused
done
if [ "${VAX_GUEST:-}" = skip ]; then
  echo "SKIPPED: building and running EXT with hand-Twice.mar's object on the VAX (VAX_GUEST=skip)"
elif ../../../tools/vax-assemble -available; then
  mkdir work/guest
  if ! ../../../tools/vax-do -o work/guest -get TWICE.CNT guest-counted.com hand-Twice.mar work/other/Helper.obj \
       >work/out 2>&1; then
    echo "guest-counted.com failed on the VAX:" >>result
    cat work/out >>result
  else
    cp work/guest/TWICE.CNT work/twice.obj
    quiet -target vax-dec-vms -vax-objects -output-dir glibs -library-path olibs -library EXT ExtLib.mod Thrice.mar twice.obj
    mkdir work/main-macro32 work/main-objects
    quiet -target vax-dec-vms -library-path glibs -library-path olibs -output-dir main-macro32 -o useolb -build ExtUse.mod
    quiet -target vax-dec-vms -vax-objects -library-path glibs -library-path olibs -shared-libraries \
      -output-dir main-objects -o useshr -build ExtUse.mod
    vax_do guest-library.com guest-library.expected work/olibs/vax-dec-vms/O2/*.obj work/olibs/vax-dec-vms/O2/*.mar \
      work/olibs/vax-dec-vms/O2/POCRTL_*.com work/glibs/vax-dec-vms/O2/*.obj work/glibs/vax-dec-vms/O2/*.mar \
      work/glibs/vax-dec-vms/O2/EXT_*.com work/main-macro32/ExtUse.mar work/main-objects/ExtUse.obj \
      work/useolb.com work/useshr.com
  fi
else
  echo "SKIPPED: building and running EXT with hand-Twice.mar's object on the VAX (no VAX development system here)"
fi
rm -rf work
. ../../testresult.sh
