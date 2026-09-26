#!/bin/sh
. ../../testenv.sh
poc -check for-final-value.mod >result 2>&1
. ../../testresult.sh
