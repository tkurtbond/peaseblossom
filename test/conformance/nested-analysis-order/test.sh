#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedorder.mod >result
. ../../testresult.sh
