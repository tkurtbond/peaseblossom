#!/bin/sh
. ../../testenv.sh
poc -check predeclared-mutating.mod >result
. ../../testresult.sh
