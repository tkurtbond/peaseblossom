#!/bin/sh
. ../../testenv.sh
poc -check-syntax param-mark.mod >result 2>&1
. ../../testresult.sh
