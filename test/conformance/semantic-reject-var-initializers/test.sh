#!/bin/sh
. ../../testenv.sh
poc -check initializers.mod >result 2>&1
. ../../testresult.sh
