#!/bin/sh
. ../../testenv.sh
# Phase 14: record and array constants written to a .sym file whole (and
# constant field initializers as their values), and an importer folding
# them, shown by its exported view
: >result
poc -emit-interface shapes.mod >>result 2>&1
cat shapes.sym >>result
echo "--- user:" >>result
poc -show-interface user.mod >>result 2>&1
poc -emit-interface user.mod >/dev/null 2>&1
echo "--- third:" >>result
poc -show-interface third.mod >>result 2>&1
. ../../testresult.sh
