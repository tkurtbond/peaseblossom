#!/bin/sh
. ../../testenv.sh
poc -check type-mismatch.mod >result
. ../../testresult.sh
