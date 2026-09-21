#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedscopes.mod >result
. ../../testresult.sh
