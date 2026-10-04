#!/bin/sh
. ../../testenv.sh
# Phase 14: record and array literals the checker accepts
poc -check literals.mod >result 2>&1
. ../../testresult.sh
