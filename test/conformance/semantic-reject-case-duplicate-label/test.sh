#!/bin/sh
. ../../testenv.sh
poc -check case-duplicate-label.mod >result 2>&1
. ../../testresult.sh
