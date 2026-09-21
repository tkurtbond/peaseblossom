#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedbasic.mod >result
. ../../testresult.sh
