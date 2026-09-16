#!/bin/sh
. ../../testenv.sh
poc -check call-not-procedure.mod >result
. ../../testresult.sh
