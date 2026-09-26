#!/bin/sh
. ../../testenv.sh
poc -check self-referential.mod >result 2>&1
. ../../testresult.sh
