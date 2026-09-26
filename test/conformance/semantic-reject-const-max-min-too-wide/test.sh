#!/bin/sh
. ../../testenv.sh
poc -check reject-const-max-min-too-wide.mod >result 2>&1
. ../../testresult.sh
