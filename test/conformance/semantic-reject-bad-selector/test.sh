#!/bin/sh
. ../../testenv.sh
poc -check bad-selector.mod >result
. ../../testresult.sh
