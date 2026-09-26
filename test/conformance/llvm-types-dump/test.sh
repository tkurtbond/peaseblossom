#!/bin/sh
. ../../testenv.sh
poc -dump-llvm-types types-dump.mod >result 2>&1
. ../../testresult.sh
