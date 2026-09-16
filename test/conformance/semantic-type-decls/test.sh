#!/bin/sh
. ../../testenv.sh
poc -check type-decls.mod >result
. ../../testresult.sh
