#!/bin/sh
. ../../testenv.sh
poc -check receiver-bad-type.mod >result
. ../../testresult.sh
