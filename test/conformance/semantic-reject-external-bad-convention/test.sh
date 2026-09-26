#!/bin/sh
. ../../testenv.sh
poc -check external-bad-convention.mod >result 2>&1
. ../../testresult.sh
