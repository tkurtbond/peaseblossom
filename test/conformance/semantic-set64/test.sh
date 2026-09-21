#!/bin/sh
. ../../testenv.sh
# SYSTEM.SET64 in the checker, one line per statement and model, "ok" if it is
# accepted. A SET is 32 bits under both models; a constant set is typed by its
# value ({0, 31} a SET, {0, 32} a SET64, {} a SET), a constructor with a
# variable element only by its constant elements; a SET goes into a SET64 and
# not the other way.
: >result
while IFS= read -r stmt
do
  printf 'MODULE t;\n  IMPORT SYSTEM;\n  CONST big = {2, 40}; small = {2, 31};\n  VAR s: SET; q: SYSTEM.SET64; t: SYSTEM.SET32; n: INTEGER; h: HUGEINT;\n    r: RECORD f: SYSTEM.SET64 END;\nBEGIN\n  %s\nEND t.\n' "$stmt" >t.mod
  for model in -O2 -OC
  do
    printf '%-4s %-38s ' "$model" "$stmt" >>result
    poc $model -check t.mod >t.out 2>&1
    if grep -q '^semantic OK' t.out
    then echo ok >>result
    else sed -n '1s/.*error: //p' t.out >>result
    fi
  done
done <statements.txt
rm -f t.mod t.out
. ../../testresult.sh
