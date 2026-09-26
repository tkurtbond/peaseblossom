#!/bin/sh
. ../../testenv.sh
poc -check integer-literal-overflow.mod >result 2>&1
. ../../testresult.sh
