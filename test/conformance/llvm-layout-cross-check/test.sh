#!/bin/sh
. ../../testenv.sh
poc -dump-layout mixed.mod >result 2>&1
. ../../testresult.sh
