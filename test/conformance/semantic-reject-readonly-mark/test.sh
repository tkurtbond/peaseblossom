#!/bin/sh
. ../../testenv.sh
poc -check readonly-mark.mod >result
. ../../testresult.sh
