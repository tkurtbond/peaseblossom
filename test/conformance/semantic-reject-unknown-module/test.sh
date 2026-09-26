#!/bin/sh
. ../../testenv.sh
poc -check unknown-module.mod >result 2>&1
. ../../testresult.sh
