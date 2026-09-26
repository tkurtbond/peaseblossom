#!/bin/sh
. ../../testenv.sh
poc -check procedure-types.mod >result 2>&1
. ../../testresult.sh
