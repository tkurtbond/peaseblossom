#!/bin/sh
. ../../testenv.sh
poc -check with-not-implemented.mod >result
. ../../testresult.sh
