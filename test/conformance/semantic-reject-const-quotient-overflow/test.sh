#!/bin/sh
. ../../testenv.sh
poc -check const-quotient-overflow.mod >result 2>&1
. ../../testresult.sh
