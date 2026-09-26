#!/bin/sh
. ../../testenv.sh
poc -check with-bad-extension.mod >result 2>&1
. ../../testresult.sh
