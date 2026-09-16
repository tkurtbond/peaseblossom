#!/bin/sh
. ../../testenv.sh
poc -check forward-alias.mod >result
. ../../testresult.sh
