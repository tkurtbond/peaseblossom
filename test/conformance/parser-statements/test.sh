#!/bin/sh
. ../../testenv.sh
poc -check-syntax statements.mod >result 2>&1
. ../../testresult.sh
