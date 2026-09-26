#!/bin/sh
. ../../testenv.sh
poc -check param-count-mismatch.mod >result 2>&1
. ../../testresult.sh
