#!/bin/sh
. ../../testenv.sh
poc -check-syntax param-mark.mod >result
. ../../testresult.sh
