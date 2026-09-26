#!/bin/sh
. ../../testenv.sh
poc -check const-decls.mod >result 2>&1
. ../../testresult.sh
