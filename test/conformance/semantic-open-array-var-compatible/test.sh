#!/bin/sh
. ../../testenv.sh
poc -check openvar.mod >result 2>&1
. ../../testresult.sh
