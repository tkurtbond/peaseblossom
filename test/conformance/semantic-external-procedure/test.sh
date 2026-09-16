#!/bin/sh
. ../../testenv.sh
poc -check external-procedure.mod >result
. ../../testresult.sh
