#!/bin/sh
. ../../testenv.sh
poc -check record-array-result.mod >result
. ../../testresult.sh
