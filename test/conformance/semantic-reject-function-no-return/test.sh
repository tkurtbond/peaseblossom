#!/bin/sh
. ../../testenv.sh
poc -check function-no-return.mod >result 2>&1
. ../../testresult.sh
