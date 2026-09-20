#!/bin/sh
. ../../testenv.sh
poc -check const-fold-narrow.mod >result
. ../../testresult.sh
