#!/bin/sh
. ../../testenv.sh
# What LONG(x) and SHORT(x) are for every integer type x, under both size
# models: the narrowest of SYSTEM.INT8..INT64 the result can be assigned to
# ("-" if the call is rejected). The table was cross-checked against real voc
# (2026-09-20) by the same loop over `voc -s`: the 28 rows for SYSTEM.INTn and
# HUGEINT are identical, and so are LONG/SHORT of INTEGER and SHORTINT/LONGINT
# where the report defines them. The two rows poc rejects and voc accepts are
# LONG(LONGINT) and SHORT(SHORTINT): a voc extension the report does not have.
: >result
for model in -O2 -OC
do
  for fn in LONG SHORT
  do
    echo "### $model $fn" >>result
    for src in SYSTEM.INT8 SHORTINT SYSTEM.INT16 INTEGER SYSTEM.INT32 LONGINT SYSTEM.INT64 HUGEINT
    do
      res=-
      for dst in SYSTEM.INT8 SYSTEM.INT16 SYSTEM.INT32 SYSTEM.INT64
      do
        printf 'MODULE P;\n  IMPORT SYSTEM;\n  VAR x: %s; y: %s;\nBEGIN\n  y := %s(x)\nEND P.\n' \
          "$src" "$dst" "$fn" >P.mod
        if poc $model -check P.mod >/dev/null 2>&1; then res=$dst; break; fi
      done
      printf '  %-14s -> %s\n' "$src" "$res" >>result
    done
  done
done
rm -f P.mod
. ../../testresult.sh
