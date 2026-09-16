#!/bin/sh
. ../../testenv.sh
poc -dump-tokens unterminated-string.txt >result
. ../../testresult.sh
