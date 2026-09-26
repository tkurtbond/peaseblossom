#!/bin/sh
. ../../testenv.sh
poc -check assign-type-mismatch.mod >result 2>&1
. ../../testresult.sh
