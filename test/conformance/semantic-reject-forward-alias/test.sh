#!/bin/sh
. ../../testenv.sh
poc -check forward-alias.mod >result 2>&1
. ../../testresult.sh
