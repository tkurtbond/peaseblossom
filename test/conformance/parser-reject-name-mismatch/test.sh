#!/bin/sh
. ../../testenv.sh
poc -check-syntax name-mismatch.mod >result 2>&1
. ../../testresult.sh
