#!/bin/sh
. ../../testenv.sh
poc -dump-layout node-tree.mod >result
. ../../testresult.sh
