#!/bin/sh
. ../../testenv.sh
poc -check-syntax trees.mod >result
. ../../testresult.sh
