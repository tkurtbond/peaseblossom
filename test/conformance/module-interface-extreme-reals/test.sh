#!/bin/sh
. ../../testenv.sh
mkdir -p round1 round2
poc -output-dir round1 -emit-interface extreme.mod >result 2>&1
cat round1/extreme.sym >>result
poc -output-dir round2 -emit-interface round1/extreme.sym >/dev/null
if diff round1/extreme.sym round2/extreme.sym >/dev/null
then echo "round trip exact" >>result
else { echo "ROUND-TRIP MISMATCH:"; diff round1/extreme.sym round2/extreme.sym; } >>result
fi
. ../../testresult.sh
