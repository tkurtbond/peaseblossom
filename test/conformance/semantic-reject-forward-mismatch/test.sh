#!/bin/sh
. ../../testenv.sh
poc -check forward-mismatch.mod >result
. ../../testresult.sh
