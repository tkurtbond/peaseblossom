#!/bin/sh
. ../../testenv.sh
# Under -O2 (the default) and -OC: the two runs print the same.
poc_build_run strindex.mod
poc -OC -o "$(basename "$PWD")" -build strindex.mod >result.OC 2>&1
"./$(basename "$PWD")" >>result.OC
cmp -s result result.OC || echo "-OC output differs" >>result
rm -f result.OC
. ../../testresult.sh
