#!/bin/sh
. ../../testenv.sh
poc -check undeclared.mod >result
. ../../testresult.sh
