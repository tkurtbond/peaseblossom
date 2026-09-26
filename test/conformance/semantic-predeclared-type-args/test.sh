#!/bin/sh
. ../../testenv.sh
poc -check predeclared-type-args.mod >result 2>&1
. ../../testresult.sh
