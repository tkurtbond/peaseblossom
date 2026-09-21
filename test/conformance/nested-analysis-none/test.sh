#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestednone.mod >result
. ../../testresult.sh
