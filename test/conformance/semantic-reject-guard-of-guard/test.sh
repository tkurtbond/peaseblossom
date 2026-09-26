#!/bin/sh
. ../../testenv.sh
poc -check guardguard.mod >result 2>&1
. ../../testresult.sh
