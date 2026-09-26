#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedbasic.mod >result 2>&1
. ../../testresult.sh
