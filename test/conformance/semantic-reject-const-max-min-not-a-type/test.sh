#!/bin/sh
. ../../testenv.sh
poc -check reject-const-max-min-not-a-type.mod >result 2>&1
. ../../testresult.sh
