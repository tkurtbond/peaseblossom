#!/bin/sh
. ../../testenv.sh
poc -dump-tokens unterminated-string.txt >result 2>&1
. ../../testresult.sh
