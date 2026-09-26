#!/bin/sh
. ../../testenv.sh
poc -check withleaf.mod >result 2>&1
. ../../testresult.sh
