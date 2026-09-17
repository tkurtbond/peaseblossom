#!/bin/sh
. ../../testenv.sh
poc -emit-interface lib.mod >/dev/null
cp lib.sym result
. ../../testresult.sh
