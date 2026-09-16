#!/bin/sh
. ../../testenv.sh
poc -check-syntax declarations.mod >result
. ../../testresult.sh
