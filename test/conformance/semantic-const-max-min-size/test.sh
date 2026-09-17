#!/bin/sh
. ../../testenv.sh
poc -check const-max-min-size.mod >result
. ../../testresult.sh
