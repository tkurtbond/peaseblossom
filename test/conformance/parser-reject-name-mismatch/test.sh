#!/bin/sh
. ../../testenv.sh
poc -check-syntax name-mismatch.mod >result
. ../../testresult.sh
