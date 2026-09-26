#!/bin/sh
. ../../testenv.sh
poc -dump-tokens vocabulary.txt >result 2>&1
. ../../testresult.sh
