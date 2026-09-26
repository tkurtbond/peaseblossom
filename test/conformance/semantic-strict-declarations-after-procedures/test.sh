#!/bin/sh
. ../../testenv.sh
poc -strict -check strict.mod >result 2>&1
. ../../testresult.sh
