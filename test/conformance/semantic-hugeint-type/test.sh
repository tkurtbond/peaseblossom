#!/bin/sh
. ../../testenv.sh
poc -check hugeint.mod >result
. ../../testresult.sh
