#!/bin/sh
. ../../testenv.sh
poc -check reject-same-line-type-cycles.mod >result 2>&1
. ../../testresult.sh
