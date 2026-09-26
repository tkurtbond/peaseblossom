#!/bin/sh
. ../../testenv.sh
poc -check-syntax call-of-result.mod >result 2>&1
. ../../testresult.sh
