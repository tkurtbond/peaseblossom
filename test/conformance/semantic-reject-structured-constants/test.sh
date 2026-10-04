#!/bin/sh
. ../../testenv.sh
# Phase 14: what a record or array constant may not be or do
poc -emit-interface lib.mod >/dev/null
: >result
for m in constants client; do
  echo "== $m" >>result
  poc -check $m.mod >>result 2>&1
done
. ../../testresult.sh
