#!/bin/sh
. ../../testenv.sh
poc -check reject-decl-order-const-forward-type.mod >result 2>&1
. ../../testresult.sh
