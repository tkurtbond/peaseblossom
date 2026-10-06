#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 1: a module's initializer is <MODULE>_INIT, unhashed,
# so a module name is at most 26 characters (the design's section 5)
poc -dump-vax-names ABCDEFGHIJKLMNOPQRSTUVWXYZ.mod >result 2>&1
echo "exit $?" >>result
poc -dump-vax-names ABCDEFGHIJKLMNOPQRSTUVWXYZa.mod >>result 2>&1
echo "exit $?" >>result
. ../../testresult.sh
