#!/bin/sh
. ../../testenv.sh
poc -check const-value-functions.mod >result 2>&1
. ../../testresult.sh
