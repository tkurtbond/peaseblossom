#!/bin/sh
. ../../testenv.sh
# PLAN.md, "Ongoing language enhancements", item 3: SYSTEM.VAL(
# SYSTEM.ADDRESS, E) takes an external procedure E; any other use of E's
# name as a value is still refused, as are a nested and a type-bound
# procedure in VAL; -strict reports the allowed one.
poc -check valexternal.mod >result 2>&1
echo "== -strict" >>result
poc -strict -check strictaddress.mod >>result 2>&1
. ../../testresult.sh
