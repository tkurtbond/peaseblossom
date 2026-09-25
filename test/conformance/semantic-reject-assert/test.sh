#!/bin/sh
. ../../testenv.sh
poc -check assert-errors.mod >result
. ../../testresult.sh
