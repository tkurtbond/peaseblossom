#!/bin/sh
. ../../testenv.sh
mkdir -p round1 round2
poc -output-dir round1 -emit-interface handlers.mod >/dev/null
poc -output-dir round2 -emit-interface round1/Handlers.sym >/dev/null
if diff round1/Handlers.sym round2/Handlers.sym >/dev/null
then
  cat round1/Handlers.sym >result
else
  { echo "ROUND-TRIP MISMATCH:"; diff round1/Handlers.sym round2/Handlers.sym; } >result
fi
. ../../testresult.sh
