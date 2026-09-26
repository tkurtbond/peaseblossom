#!/bin/sh
. ../../testenv.sh
poc -check late.mod >result 2>&1
. ../../testresult.sh
