#!/bin/sh
. ../../testenv.sh
poc -check var-decls.mod >result
. ../../testresult.sh
