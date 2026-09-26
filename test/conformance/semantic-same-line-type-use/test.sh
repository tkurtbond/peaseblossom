#!/bin/sh
. ../../testenv.sh
poc -check same-line-type-use.mod >result 2>&1
. ../../testresult.sh
