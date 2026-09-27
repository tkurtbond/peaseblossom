#!/bin/sh
. ../../testenv.sh
# Under both size models: a pattern that fits LONGINT is one under -O2 too.
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build hexpatterns.mod >>result 2>&1
  "./$exe" >>result
done
. ../../testresult.sh
