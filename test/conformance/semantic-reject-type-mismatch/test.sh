#!/bin/sh
. ../../testenv.sh
poc -check type-mismatch.mod >result 2>&1
. ../../testresult.sh
