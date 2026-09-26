#!/bin/sh
. ../../testenv.sh
poc -check type-bound-procedures.mod >result 2>&1
. ../../testresult.sh
