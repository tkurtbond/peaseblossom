#!/bin/sh
. ../../testenv.sh
poc -check const-decls.mod >result
. ../../testresult.sh
