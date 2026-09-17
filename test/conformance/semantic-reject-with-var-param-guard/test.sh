#!/bin/sh
. ../../testenv.sh
poc -check withvarparamguard.mod >result
. ../../testresult.sh
