#!/bin/sh
. ../../testenv.sh
poc -dump-nested nestedrecursion.mod >result
. ../../testresult.sh
