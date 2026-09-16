#!/bin/sh
. ../../testenv.sh
poc -check return-value-in-module.mod >result
. ../../testresult.sh
