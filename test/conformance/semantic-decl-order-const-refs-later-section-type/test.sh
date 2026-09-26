#!/bin/sh
. ../../testenv.sh
poc -check decl-order-const-refs-later-section-type.mod >result 2>&1
. ../../testresult.sh
