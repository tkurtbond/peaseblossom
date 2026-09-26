#!/bin/sh
. ../../testenv.sh
poc -check const-fold-narrow.mod >result 2>&1
. ../../testresult.sh
