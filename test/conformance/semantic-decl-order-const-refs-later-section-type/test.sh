#!/bin/sh
. ../../testenv.sh
poc -check decl-order-const-refs-later-section-type.mod >result
. ../../testresult.sh
