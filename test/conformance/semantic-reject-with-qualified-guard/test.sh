#!/bin/sh
. ../../testenv.sh
poc -emit-interface withlib.mod >/dev/null
poc -check withqualifiedguard.mod >result 2>&1
. ../../testresult.sh
