#!/bin/sh
. ../../testenv.sh
poc -check bad-record-base.mod >result
. ../../testresult.sh
