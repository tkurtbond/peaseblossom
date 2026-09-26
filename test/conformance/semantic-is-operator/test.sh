#!/bin/sh
. ../../testenv.sh
poc -check is-operator.mod >result 2>&1
. ../../testresult.sh
