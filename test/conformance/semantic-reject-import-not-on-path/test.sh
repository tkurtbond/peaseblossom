#!/bin/sh
. ../../testenv.sh
(cd lib && poc -emit-interface greeter.mod >/dev/null)
poc -check client.mod >result
. ../../testresult.sh
