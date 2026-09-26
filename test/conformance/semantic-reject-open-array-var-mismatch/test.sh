#!/bin/sh
. ../../testenv.sh
poc -check openvarbad.mod >result 2>&1
. ../../testresult.sh
