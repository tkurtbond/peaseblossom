#!/bin/sh
. ../../testenv.sh
poc -dump-tokens vocabulary.txt >result
. ../../testresult.sh
