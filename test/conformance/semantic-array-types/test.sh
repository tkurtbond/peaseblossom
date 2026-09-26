#!/bin/sh
. ../../testenv.sh
poc -check array-types.mod >result 2>&1
. ../../testresult.sh
