#!/bin/sh
. ../../testenv.sh
poc -check type-guard.mod >result
. ../../testresult.sh
