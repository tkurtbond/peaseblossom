#!/bin/sh
. ../../testenv.sh
poc -emit-interface lib.mod >/dev/null
poc -check client.mod >result 2>&1
. ../../testresult.sh
