#!/bin/sh
. ../../testenv.sh
poc -check unknown-module.mod >result
. ../../testresult.sh
