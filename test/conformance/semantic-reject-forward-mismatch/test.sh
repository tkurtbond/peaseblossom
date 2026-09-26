#!/bin/sh
. ../../testenv.sh
poc -check forward-mismatch.mod >result 2>&1
. ../../testresult.sh
