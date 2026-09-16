#!/bin/sh
. ../../testenv.sh
poc -dump-tokens unterminated-comment.txt >result
. ../../testresult.sh
