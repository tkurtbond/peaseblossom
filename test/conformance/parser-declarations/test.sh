#!/bin/sh
. ../../testenv.sh
poc -check-syntax declarations.mod >result 2>&1
. ../../testresult.sh
