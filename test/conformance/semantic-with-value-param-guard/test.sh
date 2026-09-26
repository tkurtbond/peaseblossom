#!/bin/sh
. ../../testenv.sh
poc -check withvalueparamguard.mod >result 2>&1
. ../../testresult.sh
