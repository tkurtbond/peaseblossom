#!/bin/sh
. ../../testenv.sh
poc -check direct-value-cycle.mod >result 2>&1
. ../../testresult.sh
