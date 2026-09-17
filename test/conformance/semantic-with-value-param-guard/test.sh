#!/bin/sh
. ../../testenv.sh
poc -check withvalueparamguard.mod >result
. ../../testresult.sh
