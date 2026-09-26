#!/bin/sh
. ../../testenv.sh
poc -check undeclared.mod >result 2>&1
. ../../testresult.sh
