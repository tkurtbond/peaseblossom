#!/bin/sh
. ../../testenv.sh
poc -check expressions.mod >result
. ../../testresult.sh
