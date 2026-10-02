#!/bin/sh
. ../../testenv.sh
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -check byteparams.mod >>result 2>&1
done
. ../../testresult.sh
