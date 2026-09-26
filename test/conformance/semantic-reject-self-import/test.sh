#!/bin/sh
. ../../testenv.sh
poc -check self-import.mod >result 2>&1
. ../../testresult.sh
