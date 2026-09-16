#!/bin/sh
. ../../testenv.sh
poc -check predeclared-arithmetic.mod >result
. ../../testresult.sh
