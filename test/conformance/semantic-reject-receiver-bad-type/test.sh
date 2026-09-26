#!/bin/sh
. ../../testenv.sh
poc -check receiver-bad-type.mod >result 2>&1
. ../../testresult.sh
