#!/bin/sh
. ../../testenv.sh
poc -check charstring.mod >result 2>&1
. ../../testresult.sh
