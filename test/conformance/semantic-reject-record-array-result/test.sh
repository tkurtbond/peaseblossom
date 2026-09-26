#!/bin/sh
. ../../testenv.sh
poc -check record-array-result.mod >result 2>&1
. ../../testresult.sh
