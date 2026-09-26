#!/bin/sh
. ../../testenv.sh
poc -check return-value-in-module.mod >result 2>&1
. ../../testresult.sh
