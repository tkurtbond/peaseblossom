#!/bin/sh
. ../../testenv.sh
poc -check integer-literal-minimal-type.mod >result 2>&1
. ../../testresult.sh
