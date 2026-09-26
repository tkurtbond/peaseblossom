#!/bin/sh
. ../../testenv.sh
poc -check-syntax bad-type.mod >result 2>&1
. ../../testresult.sh
