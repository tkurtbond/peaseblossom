#!/bin/sh
. ../../testenv.sh
poc -check-syntax statements.mod >result
. ../../testresult.sh
