#!/bin/sh
. ../../testenv.sh
poc -check type-guard.mod >result 2>&1
. ../../testresult.sh
