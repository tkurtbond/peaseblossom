#!/bin/sh
. ../../testenv.sh
poc -dump-llvm-types types-dump.mod >result
. ../../testresult.sh
