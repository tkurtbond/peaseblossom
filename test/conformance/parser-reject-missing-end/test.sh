#!/bin/sh
. ../../testenv.sh
poc -check-syntax missing-end.mod >result 2>&1
. ../../testresult.sh
