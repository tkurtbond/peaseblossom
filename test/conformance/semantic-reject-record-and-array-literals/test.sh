#!/bin/sh
. ../../testenv.sh
# Phase 14: each rule for record and array literals broken once
poc -emit-interface lib.mod >/dev/null
: >result
for m in literals bare selector; do
  echo "== $m" >>result
  poc -check $m.mod >>result 2>&1
done
. ../../testresult.sh
