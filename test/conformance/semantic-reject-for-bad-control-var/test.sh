#!/bin/sh
. ../../testenv.sh
poc -check for-bad-control-var.mod >result
. ../../testresult.sh
