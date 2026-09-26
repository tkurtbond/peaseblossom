#!/bin/sh
. ../../testenv.sh
poc -check readonly-mark.mod >result 2>&1
. ../../testresult.sh
