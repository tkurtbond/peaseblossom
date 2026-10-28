#!/bin/sh
. ../../testenv.sh
# doc/developer/vax-macro32-backend.md, section 13.3, proposal 9: poc
# -target vax-dec-vms -build and -library take options files, .opt files
# in any case, whose lines poc reads and adds after the -link arguments,
# as -link's are: blanks around a line dropped, a blank line and one that
# starts with "!" left out, a line that ends in "-" joined with the next.
# Value.mod built with Seven.opt (SYMBOL=SEVEN_VALUE,7, continued over two
# lines), and with a -link of the same line, which is linked once: the
# procedure is compared with expected-Value.com. The library SEVEN, from
# SevenLib.mod and Seven.opt with CR LF line ends: its manifest, compared
# with expected-SEVEN.library, records the line as a "link" line, and
# SEVEN_build.com links SEVEN.EXE with it; SevenUse.mod, built against
# SEVEN with no options file, gets it from the manifest. Then what is
# refused, each with exit status 1: an options file that is not there, one
# with an option that starts with "$", one longer than 512 characters
# when joined, one continued past its end, and an options file given to
# -build or -library for LLVM, to -compile and to -emit-interface. Where
# the VAX development system can be used (../../vaxfixture.sh), POCRTL and
# SEVEN are built there from poc's objects, and Value and SevenUse, the
# latter against SEVEN's shareable image and its object library, and run:
# each prints SEVEN_VALUE, the address of an external procedure, as 7
# (guest-options.com, guest-options.expected).
. ../../vaxfixture.sh
rm -rf work
mkdir work
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
: >result
rtl=../../../../rtl/vax
lib=libs/vax-dec-vms/O2
cp Value.mod SevenLib.mod SevenUse.mod Seven.opt work/
awk '{ printf "%s\r\n", $0 }' Seven.opt >work/SEVEN-CRLF.OPT
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls $rtl/*.Mod) $rtl/PocRtl.mar) >>result 2>&1
echo "POCRTL exit $?" >>result
run -target vax-dec-vms -library-path libs -build Value.mod Seven.opt
compare expected-Value.com Value.com
run -target vax-dec-vms -library-path libs -link SYMBOL=SEVEN_VALUE,7 -o twice -build Value.mod Seven.opt
echo "twice.com: $(grep -c '^SYMBOL=SEVEN_VALUE,7$' work/twice.com) SYMBOL line" >>result
run -target vax-dec-vms -output-dir libs -library-path libs -library SEVEN SevenLib.mod SEVEN-CRLF.OPT
grep -v '^poc ' work/$lib/SEVEN.library >work/manifest
compare expected-SEVEN.library manifest
echo "SEVEN_build.com: $(grep -c '^SYMBOL=SEVEN_VALUE,7$' work/$lib/SEVEN_build.com) SYMBOL line" >>result
run -target vax-dec-vms -library-path libs -o useolb -build SevenUse.mod
echo "useolb.com: $(grep -c '^SYMBOL=SEVEN_VALUE,7$' work/useolb.com) SYMBOL line" >>result
printf 'SYMBOL=A,1\n$ WRITE SYS$OUTPUT "ended"\n' >work/Dollar.opt
awk 'BEGIN { s = "SYMBOL=LONG,"; while (length(s) < 300) s = s "1"; print s "-"
             s = ""; while (length(s) < 213) s = s "1"; print s }' >work/Long.opt
printf 'SYMBOL=A,1\nSYMBOL=B,-\n' >work/Dangling.opt
for opt in missing.opt Dollar.opt Long.opt Dangling.opt; do
  run -target vax-dec-vms -library-path libs -build Value.mod $opt
  run -target vax-dec-vms -output-dir refused -library-path libs -library OTHER Value.mod $opt
  [ -d work/refused/vax-dec-vms/O2 ] && echo "refused/vax-dec-vms/O2 made" >>result
  rm -rf work/refused
done
run -build Value.mod Seven.opt
run -output-dir refused -library OTHER SevenLib.mod Seven.opt
run -target vax-dec-vms -library-path libs -compile Value.mod Seven.opt
run -target vax-dec-vms -library-path libs -emit-interface Value.mod Seven.opt
if [ "${VAX_GUEST:-}" = skip ]; then
  echo "SKIPPED: building and running Value and SevenUse on the VAX (VAX_GUEST=skip)"
elif ../../../tools/vax-assemble -available; then
  (cd work && poc -target vax-dec-vms -vax-objects -output-dir olibs -library POCRTL $(LC_ALL=C ls $rtl/*.Mod) \
     $rtl/PocRtl.mar) >work/out 2>&1 || { echo "POCRTL from objects failed:" >>result; cat work/out >>result; }
  quiet -target vax-dec-vms -vax-objects -output-dir olibs -library-path olibs -library SEVEN SevenLib.mod Seven.opt
  mkdir work/main-value work/main-macro32 work/main-objects
  quiet -target vax-dec-vms -vax-objects -library-path olibs -output-dir main-value -build Value.mod Seven.opt
  quiet -target vax-dec-vms -library-path olibs -output-dir main-macro32 -o useolb -build SevenUse.mod
  quiet -target vax-dec-vms -vax-objects -library-path olibs -shared-libraries -output-dir main-objects -o useshr \
    -build SevenUse.mod
  vax_do guest-options.com guest-options.expected work/olibs/vax-dec-vms/O2/*.obj work/olibs/vax-dec-vms/O2/*.mar \
    work/olibs/vax-dec-vms/O2/*_*.com work/main-value/Value.obj work/main-macro32/SevenUse.mar \
    work/main-objects/SevenUse.obj work/Value.com work/useolb.com work/useshr.com
else
  echo "SKIPPED: building and running Value and SevenUse on the VAX (no VAX development system here)"
fi
rm -rf work
. ../../testresult.sh
