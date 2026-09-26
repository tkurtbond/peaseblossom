#!/bin/sh
. ../../testenv.sh
poc -check procedure-value.mod >result 2>&1
. ../../testresult.sh
