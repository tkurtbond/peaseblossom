#!/bin/sh
. ../../testenv.sh
poc -check designators.mod >result 2>&1
. ../../testresult.sh
