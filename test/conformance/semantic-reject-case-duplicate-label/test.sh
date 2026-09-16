#!/bin/sh
. ../../testenv.sh
poc -check case-duplicate-label.mod >result
. ../../testresult.sh
