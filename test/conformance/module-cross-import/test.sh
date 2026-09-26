#!/bin/sh
. ../../testenv.sh
poc -emit-interface trees.mod >/dev/null
poc -check client.mod >result 2>&1
. ../../testresult.sh
