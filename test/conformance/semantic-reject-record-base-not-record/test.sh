#!/bin/sh
. ../../testenv.sh
poc -check bad-record-base.mod >result 2>&1
. ../../testresult.sh
