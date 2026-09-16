#!/bin/sh
. ../../testenv.sh
poc -check with-statement.mod >result
. ../../testresult.sh
