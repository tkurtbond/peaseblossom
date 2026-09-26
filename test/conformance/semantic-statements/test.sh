#!/bin/sh
. ../../testenv.sh
poc -check statements.mod >result 2>&1
. ../../testresult.sh
