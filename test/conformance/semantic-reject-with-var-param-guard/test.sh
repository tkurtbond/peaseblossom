#!/bin/sh
. ../../testenv.sh
poc -check withvarparamguard.mod >result 2>&1
. ../../testresult.sh
