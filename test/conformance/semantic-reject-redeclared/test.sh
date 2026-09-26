#!/bin/sh
. ../../testenv.sh
poc -check redeclared.mod >result 2>&1
. ../../testresult.sh
