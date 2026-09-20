#!/bin/sh
. ../../testenv.sh
# The .sym under each size model, and each read back as source: a value
# printed wrongly (or as a bare "-") does not survive being parsed and
# printed again unchanged.
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  rm -rf round1 round2; mkdir round1 round2
  poc $model -output-dir round1 -emit-interface minvalues.mod >/dev/null
  cat round1/minvalues.sym >>result
  poc $model -output-dir round2 -emit-interface round1/minvalues.sym >/dev/null
  if diff round1/minvalues.sym round2/minvalues.sym >/dev/null
  then echo "round trip: identical" >>result
  else { echo "ROUND-TRIP MISMATCH:"; diff round1/minvalues.sym round2/minvalues.sym; } >>result
  fi
done
rm -rf round1 round2
. ../../testresult.sh
