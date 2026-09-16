#!/bin/sh
. ../../testenv.sh
poc -check-syntax bad-type.mod >result
. ../../testresult.sh
