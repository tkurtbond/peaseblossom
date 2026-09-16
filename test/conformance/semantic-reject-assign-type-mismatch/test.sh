#!/bin/sh
. ../../testenv.sh
poc -check assign-type-mismatch.mod >result
. ../../testresult.sh
