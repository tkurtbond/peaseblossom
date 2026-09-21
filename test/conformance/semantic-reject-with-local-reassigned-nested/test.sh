#!/bin/sh
. ../../testenv.sh
poc -check withnested.mod >result
. ../../testresult.sh
