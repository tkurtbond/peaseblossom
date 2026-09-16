#!/bin/sh
. ../../testenv.sh
poc -check redeclared.mod >result
. ../../testresult.sh
