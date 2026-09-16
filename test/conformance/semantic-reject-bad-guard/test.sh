#!/bin/sh
. ../../testenv.sh
poc -check bad-guard.mod >result
. ../../testresult.sh
