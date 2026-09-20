#!/bin/sh
. ../../testenv.sh
poc -check const-fold-overflow.mod >result
. ../../testresult.sh
