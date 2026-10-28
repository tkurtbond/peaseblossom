#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 4b: the records poc -emit-vax-object writes
# (doc/developer/vax-object-language.md, section 15), which the image
# compared by every VAX fixture does not show, printed by vax-image
# -records for three modules - an empty one, one with records and their
# descriptors, one with type-bound procedures across modules - each
# against its expected-<Module>.records. The creation time is fixed by
# SOURCE_DATE_EPOCH (2026-10-18 00:00 UTC), and poc's version in the LNM
# record and that record's length are left out.
vax_image=${VAX_IMAGE:-../../../build/bin/vax-image}
SOURCE_DATE_EPOCH=1792281600; export SOURCE_DATE_EPOCH
: >result
rm -f *.obj *.sym *.mar Vax*.records
for source in ../vax-empty-module/VaxEmpty ../vax-var-records/VaxVarRecords ../vax-type-bound/VaxMethods; do
  module=${source##*/}
  poc -import-path "${source%/*}" -emit-vax-object "$source.mod" >/dev/null 2>>result
  echo "$module exit $?" >>result
  "$vax_image" -records "$module.obj" 2>&1 \
    | sed '/ HDR, [0-9]* bytes$/{N;s/ HDR, [0-9]* bytes\(\n  LNM "Peaseblossom poc\) [^"]*"/ HDR\1"/;}' >"$module.records"
  if diff "$module.records" "expected-$module.records" >records-diff 2>&1; then
    echo "$module.records matches expected-$module.records" >>result
  else
    echo "$module.records differs from expected-$module.records:" >>result
    cat records-diff >>result
  fi
done
rm -f records-diff
. ../../testresult.sh
