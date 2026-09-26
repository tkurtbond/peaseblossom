#!/bin/sh
. ../../testenv.sh
poc -dump-layout node-tree.mod >result 2>&1
. ../../testresult.sh
