#!/bin/sh
. ../../testenv.sh
poc -check predeclared-type-args.mod >result
. ../../testresult.sh
