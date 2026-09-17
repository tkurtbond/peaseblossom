#!/bin/sh
. ../../testenv.sh
(cd lib && poc -emit-interface greeter.mod >/dev/null)
poc -import-path lib -check client.mod >result
. ../../testresult.sh
