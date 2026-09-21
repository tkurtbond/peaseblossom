#!/bin/sh
. ../../testenv.sh
# A CASE label must lie in the range of the selector's type (voc: err 60,
# "wrong type of case label", which looks at a range's low end only): one
# line per statement and model, "ok" if the checker accepts it. A SHORTINT is
# one byte under -O2 and two under -OC, an INTEGER two and four, a LONGINT
# four and eight. Before this the checker took any label and the generated
# code compared a one-byte selector with a two-byte constant.
: >result
while IFS= read -r stmt
do
  printf 'MODULE t;\n  IMPORT SYSTEM;\n  VAR b: SYSTEM.INT8; h: SYSTEM.INT16; i: SYSTEM.INT32; q: SYSTEM.INT64;\n    s: SHORTINT; n: INTEGER; l: LONGINT; u: HUGEINT; c: CHAR;\nBEGIN\n  %s\nEND t.\n' "$stmt" >t.mod
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
