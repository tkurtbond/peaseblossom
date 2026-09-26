#!/bin/sh
. ../../testenv.sh
poc -check record-types.mod >result 2>&1
. ../../testresult.sh
