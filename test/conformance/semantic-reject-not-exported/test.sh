#!/bin/sh
. ../../testenv.sh
poc -emit-interface lib.mod >/dev/null
poc -check client.mod >result
. ../../testresult.sh
