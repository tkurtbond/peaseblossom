#!/bin/sh
. ../../testenv.sh
# Phase 11 step 2 (inventory A1): the type of a constant ORD/ABS/CHR/CAP/
# ENTIER/LONG/SHORT/ODD call, under both size models - the narrowest type
# the CONST can be assigned to, "-" if it is rejected. The list was run
# through real voc (2026-09-20, `voc -s` on the same program): the results
# agree on every row but these, all where poc keeps to the report or is
# better than voc:
#   ENTIER(3000000000.5D0) under -OC: voc dies of a Halt(-8), poc gives a
#     LONGINT (the value fits a 64-bit LONGINT)
#   LONG(3), SHORT(3): voc types a small constant as a one-byte integer of
#     its own under -OC, so LONG(3) is a SHORTINT there (INTEGER here) and
#     SHORT(3) is accepted; poc rejects SHORT(SHORTINT) as the report does
#   LONG(40000) under -O2 and LONG(3000000000) under -OC: the argument is a
#     LONGINT, which the report's LONG does not take; voc gives a HUGEINT or
#     LONGINT
: >result
for model in -O2 -OC
do
  echo "### $model" >>result
  while read -r expr
  do
    res=-
    for dst in SHORTINT INTEGER LONGINT HUGEINT REAL LONGREAL CHAR BOOLEAN
    do
      printf 'MODULE P;\n  CONST c = %s;\n  VAR v: %s;\nBEGIN\n  v := c\nEND P.\n' "$expr" "$dst" >P.mod
      if poc $model -check P.mod >/dev/null 2>&1; then res=$dst; break; fi
    done
    printf '  %-28s -> %s\n' "$expr" "$res" >>result
  done <<'LIST'
ORD("A")
ORD(0FFX)
ORD(CHR(65))
ORD("AB")
ORD("")
ORD(TRUE)
ABS(-3)
ABS(-500)
ABS(-40000)
ABS(-3000000000)
ABS(MIN(SHORTINT))
ABS(MIN(INTEGER))
ABS(MIN(LONGINT))
ABS(MIN(HUGEINT))
ABS(-2.5)
ABS(-2.5D0)
ABS(TRUE)
CHR(65)
CHR(255)
CHR(256)
CHR(-1)
CAP("a")
CAP("7")
CAP("AB")
CAP(5)
ENTIER(2.5)
ENTIER(-2.5D0)
ENTIER(70000.5D0)
ENTIER(3000000000.5D0)
ENTIER(1.0D19)
ENTIER(5)
LONG(3)
LONG(500)
LONG(40000)
LONG(3000000000)
LONG(2.5)
LONG(2.5D0)
SHORT(3)
SHORT(500)
SHORT(2.5D0)
SHORT(2.5)
SHORT(1.0D300)
ODD(3)
ODD(-4)
ODD(2.5)
ORD("a") + 1
ABS(-7) * 100
LIST
done
rm -f P.mod
. ../../testresult.sh
