#!/bin/sh
. ../../testenv.sh
poc -dump-layout basic-types.mod >result
. ../../testresult.sh
