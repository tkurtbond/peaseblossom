#!/bin/sh
. ../../testenv.sh
# poc -link for vax-dec-vms (PLAN.md, "Ongoing implementation
# enhancements"; doc/developer/vax-macro32-backend.md, section 13): each
# argument is a line of the options file of the link the procedure makes,
# after the libraries' lines. -build's procedure (VaxLink.com) is compared
# with expected-VaxLink.com and, where the VAX development system can be
# used (../../vaxfixture.sh, vax_do), run there by guest-link.com, which
# makes the object library and shareable image the lines name, and the
# program with it. A library built with -link (VAXLINK) has the lines in
# its image's link (VAXLINK_build.com) and its manifest, and a program
# built against it, from its object library or its shareable image, takes
# them with its own, each once. Then what is refused, with exit status 1
# and no procedure written: a line starting with "$", one longer than the
# 512 characters CREATE reads, one the manifest of a library the program
# uses has, and an argument longer than poc reads.
. ../../vaxfixture.sh
rm -rf libs main
rm -f VaxLink.com useolb.com useshr.com
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
# poc with a -link argument of n characters, shown as "<n characters>":
# run_long <n> <poc option before it>... -- <poc option after it>...
run_long() {
  long_n=$1; shift
  long_before=; while [ "$1" != -- ]; do long_before="$long_before $1"; shift; done; shift
  echo "== poc$long_before -link <$long_n characters> $*" >>result
  # shellcheck disable=SC2086
  poc $long_before -link "$(line "$long_n")" "$@" >>result 2>&1
  echo "exit $?" >>result
}
# a line of n characters, PSECT_ATTR= padded with blanks, ending in "!"
line() {
  awk -v n="$1" 'BEGIN { s = "PSECT_ATTR=NO_SUCH_PSECT,NOSHR"; while (length(s) < n) s = s " "; printf "%s!", substr(s, 1, n - 1) }'
}
: >result
run -target vax-dec-vms -link FOREIGN.OLB/LIBRARY -link FORSHR/SHAREABLE \
  -link PSECT_ATTR=NO_SUCH_PSECT,NOSHR -link FOREIGN.OLB/LIBRARY -build VaxLink.mod
compare expected-VaxLink.com VaxLink.com
vax_do guest-link.com guest-link.expected VaxLink.com VaxLink.mar \
  hand-foreign.mar hand-forshr.mar ../../../rtl/vax/PocRtl.mar
rtl=../../../rtl/vax
lib=libs/vax-dec-vms/O2
# in C's order: a glob follows the locale (vax-library)
run -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls $rtl/*.Mod) $rtl/PocRtl.mar
run -target vax-dec-vms -output-dir libs -library-path libs -link FOREIGN.OLB/LIBRARY \
  -link 'PSECT_ATTR=NO_SUCH_PSECT,NOSHR ! twice' -library VAXLINK VaxLinkLib.mod
compare expected-VAXLINK_build.com $lib/VAXLINK_build.com
grep '^link ' $lib/VAXLINK.library | sed 's/^/in the manifest: /' >>result
mkdir main
run -target vax-dec-vms -library-path libs -output-dir main -o useolb \
  -link SYS\$LIBRARY:STARLET.OLB/LIBRARY -link FOREIGN.OLB/LIBRARY -build VaxLinkUse.mod
compare expected-useolb.com useolb.com
run -target vax-dec-vms -library-path libs -shared-libraries -output-dir main -o useshr -build VaxLinkUse.mod
compare expected-useshr.com useshr.com
rm -f VaxLink.com useolb.com useshr.com
run -target vax-dec-vms -link '$ DELETE *.*;*' -build VaxLink.mod
run_long 512 -target vax-dec-vms -- -build VaxLink.mod
grep -c '!$' VaxLink.com | sed 's/^/512-character lines in VaxLink.com: /' >>result
rm -f VaxLink.com
run_long 513 -target vax-dec-vms -- -build VaxLink.mod
run_long 513 -target vax-dec-vms -output-dir libs -library-path libs -- -library LONG VaxLinkLib.mod
run_long 2043 -target vax-dec-vms -- -build VaxLink.mod
sed 's/^link FOREIGN.OLB\/LIBRARY$/link $ EXIT/' $lib/VAXLINK.library >manifest && mv manifest $lib/VAXLINK.library
run -target vax-dec-vms -library-path libs -output-dir main -o useolb -build VaxLinkUse.mod
ls *.com main/*.com 2>/dev/null | grep -v -e '^guest-' -e '^expected-' | sed 's/^/procedure: /' >>result
rm -rf libs main
. ../../testresult.sh
