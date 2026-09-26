#!/bin/sh
. ../../testenv.sh
poc -check mid-chain-guard.mod >result 2>&1
. ../../testresult.sh
