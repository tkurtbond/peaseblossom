#!/bin/sh
. ../../testenv.sh
poc -dump-tokens unterminated-comment.txt >result 2>&1
. ../../testresult.sh
