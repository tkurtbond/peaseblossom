#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 1 (the design's sections 5 and 5.1): two names of
# one module whose hashes collide are an error naming both, not two
# definitions of one symbol
poc -dump-vax-names VaxNameClash.mod >result 2>&1
echo "exit $?" >>result
. ../../testresult.sh
