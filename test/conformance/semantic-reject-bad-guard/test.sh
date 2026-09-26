#!/bin/sh
. ../../testenv.sh
poc -check bad-guard.mod >result 2>&1
. ../../testresult.sh
