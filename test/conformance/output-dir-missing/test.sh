#!/bin/sh
. ../../testenv.sh
poc -output-dir nosuchdir -emit-interface lib.mod >result 2>&1
. ../../testresult.sh
