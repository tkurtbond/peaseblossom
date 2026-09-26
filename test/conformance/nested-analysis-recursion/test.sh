#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedrecursion.mod >result 2>&1
. ../../testresult.sh
