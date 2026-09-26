#!/bin/sh
. ../../testenv.sh
poc -check bad-pointer-base.mod >result 2>&1
. ../../testresult.sh
