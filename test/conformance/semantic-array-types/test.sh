#!/bin/sh
. ../../testenv.sh
poc -check array-types.mod >result
. ../../testresult.sh
