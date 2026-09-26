#!/bin/sh
. ../../testenv.sh
poc -check decl-order-interleaved-sections.mod >result 2>&1
. ../../testresult.sh
