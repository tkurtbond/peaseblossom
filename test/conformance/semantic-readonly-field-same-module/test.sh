#!/bin/sh
. ../../testenv.sh
poc -check readonly-field-same-module.mod >result 2>&1
. ../../testresult.sh
