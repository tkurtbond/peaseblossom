#!/bin/sh
. ../../testenv.sh
poc -check bad.mod >result
. ../../testresult.sh
