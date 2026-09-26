#!/bin/sh
. ../../testenv.sh
poc -check bad-array-length.mod >result 2>&1
. ../../testresult.sh
