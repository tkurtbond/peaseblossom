#!/bin/sh
. ../../testenv.sh
poc -check for-bad-control-var.mod >result 2>&1
. ../../testresult.sh
