#!/bin/sh
. ../../testenv.sh
# Under -O2 (the default) and -OC: nothing here depends on the size model, so
# the two runs print the same.
poc_build_run nestedbasic.mod
poc -OC -o "$(basename "$PWD")" -build nestedbasic.mod >result.OC
"./$(basename "$PWD")" >>result.OC
cmp -s result result.OC || echo "-OC output differs" >>result
rm -f result.OC
. ../../testresult.sh
