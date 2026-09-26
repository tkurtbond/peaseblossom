#!/bin/sh
. ../../testenv.sh
poc -check const-ash-too-wide.mod >result 2>&1
. ../../testresult.sh
