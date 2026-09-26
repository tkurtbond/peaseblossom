#!/bin/sh
. ../../testenv.sh
poc -check assert-errors.mod >result 2>&1
. ../../testresult.sh
