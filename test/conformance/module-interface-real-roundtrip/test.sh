#!/bin/sh
. ../../testenv.sh
mkdir -p round1 round2
poc -output-dir round1 -emit-interface reals.mod >/dev/null
poc -output-dir round2 -emit-interface round1/reals.sym >/dev/null
if diff round1/reals.sym round2/reals.sym >/dev/null
then
  cat round1/reals.sym >result
else
  { echo "ROUND-TRIP MISMATCH:"; diff round1/reals.sym round2/reals.sym; } >result
fi
. ../../testresult.sh
