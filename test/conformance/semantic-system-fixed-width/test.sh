#!/bin/sh
. ../../testenv.sh
# SYSTEM.INT8/INT16/INT32/INT64 are integers of exactly 1/2/4/8 bytes under
# both size models, and take their place in the inclusion hierarchy by that
# width: one line per statement and model, "ok" if the checker accepts it.
# Under -O2 INT32 is LONGINT's equal and INT16 INTEGER's; under -OC INT32 is
# INTEGER's equal and INT16 SHORTINT's, and INT8 is below everything.
: >result
while IFS= read -r stmt
do
  printf 'MODULE t;\n  IMPORT SYSTEM;\n  VAR b: SYSTEM.INT8; h: SYSTEM.INT16; i: SYSTEM.INT32; q: SYSTEM.INT64;\n    s: SHORTINT; n: INTEGER; l: LONGINT; u: HUGEINT;\nBEGIN\n  %s\nEND t.\n' "$stmt" >t.mod
  for model in -O2 -OC
  do
    printf '%-4s %-46s ' "$model" "$stmt" >>result
    poc $model -check t.mod >t.out 2>&1
    if grep -q '^semantic OK' t.out
    then echo ok >>result
    else sed -n '1s/.*error: //p' t.out >>result
    fi
  done
done <statements.txt
rm -f t.mod t.out
. ../../testresult.sh
