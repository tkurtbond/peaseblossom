#!/bin/sh
. ../../testenv.sh
poc_build_run sets.mod
# the same program under -OC: a SET is 32 bits there too, so the same output
poc -OC -o "$exe" -build sets.mod >result.oc
"./$exe" >>result.oc
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
