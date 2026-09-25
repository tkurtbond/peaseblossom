#!/bin/sh
. ../../testenv.sh
poc -check for-final-value.mod >result
. ../../testresult.sh
