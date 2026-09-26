#!/bin/sh
. ../../testenv.sh
poc -check dup-field.mod >result 2>&1
. ../../testresult.sh
