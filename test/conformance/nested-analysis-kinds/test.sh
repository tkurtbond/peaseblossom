#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedkinds.mod >result
. ../../testresult.sh
