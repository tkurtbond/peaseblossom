#!/bin/sh
. ../../testenv.sh
poc -check mid-chain-guard-not-extension.mod >result 2>&1
. ../../testresult.sh
