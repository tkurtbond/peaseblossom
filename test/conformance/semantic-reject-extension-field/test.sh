#!/bin/sh
. ../../testenv.sh
poc -check fields.mod >result 2>&1
. ../../testresult.sh
