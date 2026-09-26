#!/bin/sh
. ../../testenv.sh
poc -check procedure-typed-call.mod >result 2>&1
. ../../testresult.sh
