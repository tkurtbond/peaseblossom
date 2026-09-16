#!/bin/sh
. ../../testenv.sh
poc -check direct-value-cycle.mod >result
. ../../testresult.sh
