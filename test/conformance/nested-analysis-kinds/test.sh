#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedkinds.mod >result 2>&1
. ../../testresult.sh
