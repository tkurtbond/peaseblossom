#!/bin/sh
. ../../testenv.sh
poc -check withglobalreassigned.mod >result 2>&1
. ../../testresult.sh
