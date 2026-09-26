#!/bin/sh
. ../../testenv.sh
poc -check predeclared-arithmetic.mod >result 2>&1
. ../../testresult.sh
