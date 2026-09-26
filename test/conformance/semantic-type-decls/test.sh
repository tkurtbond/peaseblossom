#!/bin/sh
. ../../testenv.sh
poc -check type-decls.mod >result 2>&1
. ../../testresult.sh
