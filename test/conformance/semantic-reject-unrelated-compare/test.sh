#!/bin/sh
. ../../testenv.sh
poc -check unrelated-compare.mod >result 2>&1
. ../../testresult.sh
