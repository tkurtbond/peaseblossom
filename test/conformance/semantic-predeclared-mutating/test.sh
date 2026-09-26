#!/bin/sh
. ../../testenv.sh
poc -check predeclared-mutating.mod >result 2>&1
. ../../testresult.sh
