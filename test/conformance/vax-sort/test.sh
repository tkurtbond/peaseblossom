#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 8): SORT
# through the generated SOR_ROUTINES, with VMSLIB's SortMerge for the
# constants SORTSHR defines: files sorted on two keys and with no
# duplicates, two files merged, records released and returned with a
# comparison routine of the program's, and records with a binary key
# released through a descriptor of the program's. The libraries POCRTL,
# VMSDEF (only the modules SortFiles imports) and VMSLIB (SortMerge alone)
# are built, and SortFiles against them. Where the VAX development system
# can be used, guest-run.com builds them there, links hand-sortsymbols.mar with
# a map, whose values SortFiles compares with SortMerge's, and runs it.
. ../../vaxfixture.sh
vms=../../../rtl/vax/vms
vmslib=../../../rtl/vax/vmslib
rtl=../../../rtl/vax
rm -rf work
mkdir work
: >result
generated="DSCDEF SORDEF SOR_ROUTINES SSDEF"
(cd work && poc -target vax-dec-vms -output-dir libs -library POCRTL $(LC_ALL=C ls ../$rtl/*.Mod) ../$rtl/PocRtl.mar) >work/out 2>&1 \
  || cat work/out >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSDEF \
  $(for m in $generated; do echo ../$vms/$m.Mod; done)) >>result 2>&1
echo "VMSDEF exit $?" >>result
(cd work && poc -target vax-dec-vms -output-dir libs -library-path libs -library VMSLIB \
  ../$vmslib/SortMerge.Mod) >>result 2>&1
echo "VMSLIB exit $?" >>result
cp SortFiles.mod work/
(cd work && poc -target vax-dec-vms -library-path libs -build SortFiles.mod) >>result 2>&1
echo "VAX build SortFiles exit $?" >>result
lib=work/libs/vax-dec-vms/O2
vax_do guest-run.com guest-run.expected $lib/*.mar $lib/*_build.com $lib/*_setup.com \
  work/SortFiles.mar work/SortFiles.com hand-sortsymbols.mar
rm -rf work
. ../../testresult.sh
