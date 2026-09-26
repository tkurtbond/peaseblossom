#!/bin/sh
. ../../testenv.sh
# Under -O2 (the default), so that 10000000000 needs HUGEINT.
: >result
poc -strict -check strict.mod >>result 2>&1
poc -check strict.mod >>result 2>&1
. ../../testresult.sh
