#!/bin/sh
. ../../testenv.sh
poc -check varparamguard.mod >result 2>&1
. ../../testresult.sh
