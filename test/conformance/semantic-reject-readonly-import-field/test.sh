#!/bin/sh
. ../../testenv.sh
poc -emit-interface trees.mod >/dev/null
poc -check client.mod >result
. ../../testresult.sh
