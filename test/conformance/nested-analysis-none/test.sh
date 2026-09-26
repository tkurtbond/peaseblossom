#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestednone.mod >result 2>&1
. ../../testresult.sh
