#!/bin/sh
. ../../testenv.sh
poc -output-dir nosuchdir -emit-interface lib.mod >result
. ../../testresult.sh
