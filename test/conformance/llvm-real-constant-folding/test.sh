#!/bin/sh
. ../../testenv.sh
# ConstantEvaluator folds a REAL expression as the generated code computes
# it (realfold.mod's comment); a REAL is the same under both size models.
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build realfold.mod >>result 2>&1
  "./$exe" >>result
done
. ../../testresult.sh
