#!/bin/sh
. ../../testenv.sh
poc -check with-statement.mod >result 2>&1
. ../../testresult.sh
