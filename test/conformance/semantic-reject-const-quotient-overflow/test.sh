#!/bin/sh
. ../../testenv.sh
poc -check const-quotient-overflow.mod >result
. ../../testresult.sh
