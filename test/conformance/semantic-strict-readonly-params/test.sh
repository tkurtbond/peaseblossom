#!/bin/sh
. ../../testenv.sh
: >result
poc -compile Lib.mod >>result 2>&1
poc -strict -check strict.mod >>result 2>&1
poc -check strict.mod >>result 2>&1
. ../../testresult.sh
