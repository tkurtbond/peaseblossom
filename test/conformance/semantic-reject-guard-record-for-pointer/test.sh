#!/bin/sh
. ../../testenv.sh
poc -check guard-record.mod >result
. ../../testresult.sh
