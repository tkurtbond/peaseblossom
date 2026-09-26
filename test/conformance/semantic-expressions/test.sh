#!/bin/sh
. ../../testenv.sh
poc -check expressions.mod >result 2>&1
. ../../testresult.sh
