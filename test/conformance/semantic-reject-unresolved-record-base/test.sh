#!/bin/sh
. ../../testenv.sh
poc -check unresolved-base.mod >result 2>&1
. ../../testresult.sh
