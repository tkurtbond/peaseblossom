#!/bin/sh
. ../../testenv.sh
poc -check bad-array-length.mod >result
. ../../testresult.sh
