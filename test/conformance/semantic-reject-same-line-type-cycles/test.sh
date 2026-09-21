#!/bin/sh
. ../../testenv.sh
poc -check reject-same-line-type-cycles.mod >result
. ../../testresult.sh
