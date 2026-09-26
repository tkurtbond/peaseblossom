#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedscopes.mod >result 2>&1
. ../../testresult.sh
