#!/bin/sh
. ../../testenv.sh
poc -check cyclic-type.mod >result 2>&1
. ../../testresult.sh
