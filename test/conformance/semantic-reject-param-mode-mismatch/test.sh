#!/bin/sh
. ../../testenv.sh
poc -check param-mode-mismatch.mod >result 2>&1
. ../../testresult.sh
