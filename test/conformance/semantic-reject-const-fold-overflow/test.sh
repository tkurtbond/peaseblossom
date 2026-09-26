#!/bin/sh
. ../../testenv.sh
poc -check const-fold-overflow.mod >result 2>&1
. ../../testresult.sh
