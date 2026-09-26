#!/bin/sh
. ../../testenv.sh
mkdir -p out
poc -output-dir out -emit-interface lib.mod >result 2>&1
cat out/lib.sym >>result
. ../../testresult.sh
