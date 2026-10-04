#!/bin/sh
. ../../testenv.sh
# Phase 14: -strict rejects a literal, once for a nested one
: >result
poc -strict -check strict.mod >>result 2>&1
poc -check strict.mod >>result 2>&1
. ../../testresult.sh
