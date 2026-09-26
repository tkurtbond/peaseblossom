#!/bin/sh
. ../../testenv.sh
poc -check procedures.mod >result 2>&1
. ../../testresult.sh
