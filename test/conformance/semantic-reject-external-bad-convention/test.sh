#!/bin/sh
. ../../testenv.sh
poc -check external-bad-convention.mod >result
. ../../testresult.sh
