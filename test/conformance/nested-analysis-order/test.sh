#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedorder.mod >result 2>&1
. ../../testresult.sh
