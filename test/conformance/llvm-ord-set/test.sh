#!/bin/sh
. ../../testenv.sh
# ORD of a SET and of a SYSTEM.SET32 under both size models: the same
# output, as the bits used fit in INTEGER's 16 under -O2.
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build ordset.mod >build.out 2>&1
  grep -v '^semantic OK' build.out >>result
  "./$exe" >>result
done
rm -f build.out
. ../../testresult.sh
