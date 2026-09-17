#!/bin/sh
. ../../testenv.sh
poc -emit-interface reals.mod >/dev/null
cp reals.sym result
. ../../testresult.sh
