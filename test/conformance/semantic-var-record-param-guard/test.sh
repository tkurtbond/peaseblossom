#!/bin/sh
. ../../testenv.sh
poc -check varparamguard.mod >result
. ../../testresult.sh
