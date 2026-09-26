#!/bin/sh
. ../../testenv.sh
mkdir -p round1 round2 oc1 oc2
{
  echo "-O2:"
  poc -output-dir round1 -emit-interface limits.mod
  cat round1/limits.sym
  echo "-OC:"
  poc -OC -output-dir oc1 -emit-interface limits.mod
  cat oc1/limits.sym
} >result 2>&1
# the interface, read back as source, reproduces itself exactly
poc -output-dir round2 -emit-interface round1/limits.sym >/dev/null
poc -OC -output-dir oc2 -emit-interface oc1/limits.sym >/dev/null
if diff round1/limits.sym round2/limits.sym >/dev/null && diff oc1/limits.sym oc2/limits.sym >/dev/null
then echo "round trip exact" >>result
else { echo "ROUND-TRIP MISMATCH:"; diff round1/limits.sym round2/limits.sym; diff oc1/limits.sym oc2/limits.sym; } >>result
fi
. ../../testresult.sh
