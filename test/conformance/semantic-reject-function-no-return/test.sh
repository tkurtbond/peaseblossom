#!/bin/sh
. ../../testenv.sh
poc -check function-no-return.mod >result
. ../../testresult.sh
