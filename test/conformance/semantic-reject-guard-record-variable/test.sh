#!/bin/sh
. ../../testenv.sh
poc -check recguard.mod >result 2>&1
. ../../testresult.sh
