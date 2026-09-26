#!/bin/sh
. ../../testenv.sh
poc -check-syntax trees.mod >result 2>&1
. ../../testresult.sh
