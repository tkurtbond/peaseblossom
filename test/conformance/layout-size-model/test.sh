#!/bin/sh
. ../../testenv.sh
poc -dump-layout basic-types.mod >result 2>&1
. ../../testresult.sh
