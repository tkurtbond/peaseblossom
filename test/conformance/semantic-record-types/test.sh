#!/bin/sh
. ../../testenv.sh
poc -check record-types.mod >result
. ../../testresult.sh
