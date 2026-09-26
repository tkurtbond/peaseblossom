#!/bin/sh
. ../../testenv.sh
poc -check hugeint.mod >result 2>&1
. ../../testresult.sh
