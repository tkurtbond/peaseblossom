#!/bin/sh
. ../../testenv.sh
poc -check exit-outside-loop.mod >result 2>&1
. ../../testresult.sh
