#!/bin/sh
. ../../testenv.sh
: >result
poc -compile Shared.mod >>result 2>&1
poc -check readonly-param.mod >>result 2>&1
. ../../testresult.sh
