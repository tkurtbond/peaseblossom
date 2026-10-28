#!/bin/sh
. ../../testenv.sh
# doc/developer/vax-macro32-backend.md, section 13.2, proposal 6: OBJCONVERT
# -COUNTED and RecordFiles' Open, Get and CreateFixed, on the VAX/VMS
# development system (guest-run.com, run by tools/vax-do). RecordsTest is built
# here with -vax-objects, and its objects sent make OBJCONVERT ready there.
# On the guest, hand-Twice.mar is assembled by MACRO, its object written in the
# counted form and turned back into an object, and both objects dumped;
# OBJCONVERT -COUNTED's refusals and RecordsTest's run are compared with
# guest-run.expected. The counted file comes back in binary (TWICE.CNT): its
# records must be the ones DUMP/RECORDS printed for the object MACRO made
# (tools/vax-objects.sh), as must the object turned back's, and poc
# -target vax-dec-vms -build must take it as an object file, twice.obj.
# Where the guest cannot be used, or VAX_GUEST is "skip", that part is
# skipped, saying so on the output but not in result, and a failure there
# is added to result, so that result is the same on every host.
. ../../vaxfixture.sh
. ../../../tools/vax-objects.sh
rtl=../../../../rtl/vax
rm -rf work
mkdir work work/guest
: >result
cp RecordsTest.mod Use.mod work/
(cd work && poc -target vax-dec-vms -vax-objects -import-path $rtl -build RecordsTest.mod) >>result 2>&1
echo "VAX build RecordsTest exit $?" >>result
if [ "${VAX_GUEST:-}" = skip ]; then
  echo "SKIPPED: running guest-run.com on the VAX (VAX_GUEST=skip)"
elif ../../../tools/vax-assemble -available; then
  if ! ../../../tools/vax-do -o work/guest -get TWICE.CNT -get TWICE.DMP -get BACK.DMP \
       guest-run.com hand-Twice.mar work/RecordsTest.com work/*.obj ../../../rtl/vax/PocRtl.mar >work/out 2>&1; then
    echo "guest-run.com failed on the VAX:" >>result
    cat work/out >>result
  else
    sed -e '$d' -e 's/\[USERS\.POC2\]/[USERS.POC]/g' work/out >work/printed
    if ! diff guest-run.expected work/printed >work/diff 2>&1; then
      echo "guest-run.com's output on the VAX differs from guest-run.expected:" >>result
      cat work/diff >>result
    fi
    counted_records work/guest/TWICE.CNT >work/counted
    dumped_records work/guest/TWICE.DMP >work/dumped
    dumped_records work/guest/BACK.DMP >work/back
    if [ ! -s work/dumped ]; then
      echo "TWICE.DMP has no records" >>result
    elif ! diff work/dumped work/counted >work/diff 2>&1; then
      echo "TWICE.CNT's records differ from TWICE.OBJ's:" >>result
      cat work/diff >>result
    fi
    if ! diff work/dumped work/back >work/diff 2>&1; then
      echo "BACK.OBJ's records differ from TWICE.OBJ's:" >>result
      cat work/diff >>result
    fi
    cp work/guest/TWICE.CNT work/twice.obj
    if ! (cd work && poc -target vax-dec-vms -build Use.mod twice.obj) >work/out 2>&1; then
      echo "poc -build did not take TWICE.CNT as twice.obj:" >>result
      cat work/out >>result
    fi
  fi
else
  echo "SKIPPED: running guest-run.com on the VAX (no VAX development system here)"
fi
rm -rf work
. ../../testresult.sh
