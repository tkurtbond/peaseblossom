#!/bin/sh
. ../../testenv.sh
poc -check bad-selector.mod >result 2>&1
. ../../testresult.sh
