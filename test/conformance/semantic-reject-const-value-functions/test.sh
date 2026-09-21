#!/bin/sh
. ../../testenv.sh
poc -check const-value-functions.mod >result
. ../../testresult.sh
