#!/bin/sh
. ../../testenv.sh
poc -check openarrays.mod >result 2>&1
. ../../testresult.sh
