#!/bin/sh
. ../../testenv.sh
poc -check readonly-field-same-module.mod >result
. ../../testresult.sh
