#!/bin/sh
. ../../testenv.sh
poc -check unrelated-compare.mod >result
. ../../testresult.sh
