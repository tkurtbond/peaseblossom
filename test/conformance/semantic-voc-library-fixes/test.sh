#!/bin/sh
. ../../testenv.sh
poc -emit-interface Ro.Mod >/dev/null
poc -check rejects.mod >result 2>&1
rm -f *.sym
. ../../testresult.sh
