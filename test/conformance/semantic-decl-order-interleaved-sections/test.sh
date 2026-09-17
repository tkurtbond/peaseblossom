#!/bin/sh
. ../../testenv.sh
poc -check decl-order-interleaved-sections.mod >result
. ../../testresult.sh
