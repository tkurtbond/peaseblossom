#!/bin/sh
. ../../testenv.sh
poc -check-syntax call-of-result.mod >result
. ../../testresult.sh
