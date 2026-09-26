#!/bin/sh
. ../../testenv.sh
poc -check var-decls.mod >result 2>&1
. ../../testresult.sh
