#!/bin/sh
. ../../testenv.sh
poc -check-syntax missing-end.mod >result
. ../../testresult.sh
