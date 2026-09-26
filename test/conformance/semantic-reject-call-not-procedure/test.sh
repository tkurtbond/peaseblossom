#!/bin/sh
. ../../testenv.sh
poc -check call-not-procedure.mod >result 2>&1
. ../../testresult.sh
