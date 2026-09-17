#!/bin/sh
. ../../testenv.sh
mkdir -p out
poc -output-dir out -emit-interface lib.mod >result
cat out/lib.sym >>result
. ../../testresult.sh
