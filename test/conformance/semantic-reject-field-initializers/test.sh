#!/bin/sh
. ../../testenv.sh
poc -check fields.mod >result 2>&1
poc -check elided.mod >>result 2>&1
. ../../testresult.sh
