#!/bin/sh
. ../../testenv.sh
poc -check integer-literal-too-wide.mod >result 2>&1
. ../../testresult.sh
