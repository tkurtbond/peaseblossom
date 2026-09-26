#!/bin/sh
. ../../testenv.sh
poc -check external-procedure.mod >result 2>&1
. ../../testresult.sh
