#!/bin/sh
. ../../testenv.sh
poc -check bad.mod >result 2>&1
. ../../testresult.sh
