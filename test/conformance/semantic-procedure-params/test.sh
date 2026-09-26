#!/bin/sh
. ../../testenv.sh
poc -check procedure-params.mod >result 2>&1
. ../../testresult.sh
