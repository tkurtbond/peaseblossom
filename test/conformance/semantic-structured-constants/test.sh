#!/bin/sh
. ../../testenv.sh
# Phase 14: record and array constants declared, selected from (a CASE
# label, an array length) and used as read-only values
poc -check constants.mod >result 2>&1
. ../../testresult.sh
