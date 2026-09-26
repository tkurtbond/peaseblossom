#!/bin/sh
. ../../testenv.sh
poc -check override-mismatch.mod >result 2>&1
. ../../testresult.sh
