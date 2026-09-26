#!/bin/sh
. ../../testenv.sh
poc -check const-max-min-size.mod >result 2>&1
. ../../testresult.sh
