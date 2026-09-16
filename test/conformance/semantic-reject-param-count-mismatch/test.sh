#!/bin/sh
. ../../testenv.sh
poc -check param-count-mismatch.mod >result
. ../../testresult.sh
