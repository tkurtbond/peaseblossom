#!/bin/sh
. ../../testenv.sh
poc -check guard-record.mod >result 2>&1
. ../../testresult.sh
