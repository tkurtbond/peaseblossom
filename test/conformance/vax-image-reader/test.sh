#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 3a: vax-image (tools/vax-image/ObjectImage.Mod),
# which runs a VAX object's records into the image VaxImage prints
# (doc/developer/vax-object-language.md, sections 14.5 and 14.7), on four
# objects MACRO wrote on the guest, as DUMP/RECORD's text: three Phase 15
# fixtures' (vax-empty-module, vax-case, vax-strings) and the second set of
# section 1, which has every kind of relocation. Each image was checked
# against MACRO's listing of the same source, every byte and relocated
# field it shows. objset2.obj is objset2.dmp's records in the counted form
# of section 10, which must give the same image.
rm -f ./*.image
poc -OC -import-path ../../../src/back/vax -o vax-image-reader -build ../../../tools/vax-image/ObjectImage.Mod >result 2>&1
for f in emptymodule case strings objset2; do
  ./vax-image-reader $f.dmp $f.image >>result 2>&1
  cat $f.image >>result
done
./vax-image-reader objset2.obj counted.image >>result 2>&1
cmp objset2.image counted.image >>result 2>&1
. ../../testresult.sh
