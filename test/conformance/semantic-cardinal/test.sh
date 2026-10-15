#!/bin/sh
. ../../testenv.sh
# The unsigned types SYSTEM.CARD8..CARD64 and SYSTEM.CARD in the checker, one
# line per statement and model, "ok" if it is accepted (AGENTS.md, "Unsigned
# integer types"): a family of their own, apart from the signed integers, so
# that mixing the two is an error and SYSTEM.VAL the only way across; within
# it LONG, SHORT and inclusion; a non-negative constant that fits is usable
# with any of them, and big, a 16-digit hexadecimal pattern, is 2^64 - 1 for
# a CARD64. Nothing here depends on SYSTEM.CARD's width.
: >result
while IFS= read -r stmt
do
  printf 'MODULE t;\n  IMPORT SYSTEM;\n  CONST big = 0FFFFFFFFFFFFFFFFH;\n  VAR a: SYSTEM.CARD8; w: SYSTEM.CARD16; d: SYSTEM.CARD32; q: SYSTEM.CARD64; c: SYSTEM.CARD;\n    n: INTEGER; h: HUGEINT; x: REAL; ch: CHAR; s: SET; adr: SYSTEM.ADDRESS; b: SYSTEM.BYTE;\n    arr: ARRAY 256 OF INTEGER;\nBEGIN\n  %s\nEND t.\n' "$stmt" >t.mod
  for model in -O2 -OC
  do
    printf '%-4s %-44s ' "$model" "$stmt" >>result
    poc $model -check t.mod >t.out 2>&1
    if grep -q '^semantic OK' t.out
    then echo ok >>result
    else sed -n '1s/.*error: //p' t.out >>result
    fi
  done
done <statements.txt
rm -f t.mod t.out
. ../../testresult.sh
