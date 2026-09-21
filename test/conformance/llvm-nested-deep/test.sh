#!/bin/sh
. ../../testenv.sh
poc_build_run nesteddeep.mod
poc -OC -o "$(basename "$PWD")" -build nesteddeep.mod >result.OC
"./$(basename "$PWD")" >>result.OC
cmp -s result result.OC || echo "-OC output differs" >>result
rm -f result.OC
. ../../testresult.sh
