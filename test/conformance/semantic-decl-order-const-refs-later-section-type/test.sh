#!/bin/sh
. ../../testenv.sh
poc -check later-section-type.mod >result 2>&1
. ../../testresult.sh
