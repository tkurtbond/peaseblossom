#!/bin/sh
. ../../testenv.sh
# SHORTCARD, CARDINAL, LONGCARD and HUGECARD in the checker, one line per
# statement and model, "ok" if it is accepted (doc/developer/
# language-extensions.md, "Predeclared unsigned types"): every inclusion
# among them and the SYSTEM.CARDn, both ways, under both models, where
# inclusion depends on the model; apart from the signed family; what LONG,
# SHORT and a constant's widening give, shown by the type a message names;
# SYSTEM.BYTE, which takes a SHORTCARD under -O2 only. The second half: a
# program's own CARDINAL, and a late one, refused as any Universe name is.
: >result
while IFS= read -r stmt
do
  cat >t.mod <<MOD
MODULE t;
  IMPORT SYSTEM;
  CONST big = 0FFFFFFFFFFFFFFFFH;
  VAR sc: SHORTCARD; ca: CARDINAL; lc: LONGCARD; hc: HUGECARD;
    a: SYSTEM.CARD8; w: SYSTEM.CARD16; d: SYSTEM.CARD32; q: SYSTEM.CARD64; c: SYSTEM.CARD;
    n: INTEGER; x: REAL; ch: CHAR; b: SYSTEM.BYTE; arr: ARRAY 256 OF INTEGER;
  PROCEDURE Byte1(y: SYSTEM.BYTE); END Byte1;
  PROCEDURE VarByte(VAR y: SYSTEM.BYTE); END VarByte;
  PROCEDURE VarCardinal(VAR y: CARDINAL); END VarCardinal;
  PROCEDURE VarLongCard(VAR y: LONGCARD); END VarLongCard;
  PROCEDURE Bytes(VAR y: ARRAY OF SYSTEM.BYTE); END Bytes;
BEGIN
  $stmt
END t.
MOD
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
# SYSTEM.CARD is as wide as ADDRESS, so it and the model's types of that width
# include each other: which ones depends on the target, so name it
for target in x86_64-unknown-linux-gnu i386-unknown-openbsd
do
  for stmt in 'c := ca' 'ca := c' 'c := lc' 'lc := c' 'c := hc' 'hc := c'
  do
    cat >t.mod <<MOD
MODULE t;
  IMPORT SYSTEM;
  VAR ca: CARDINAL; lc: LONGCARD; hc: HUGECARD; c: SYSTEM.CARD;
BEGIN
  $stmt
END t.
MOD
    for model in -O2 -OC
    do
      printf '%-24s %-4s %-8s ' "$target" "$model" "$stmt" >>result
      poc $model -target $target -check t.mod >t.out 2>&1
      if grep -q '^semantic OK' t.out
      then echo ok >>result
      else sed -n '1s/.*error: //p' t.out >>result
      fi
    done
  done
done
for program in own-types late-declaration
do
  echo "$program:" >>result
  poc -check $program.mod >>result 2>&1
  poc -strict -check $program.mod >>result 2>&1
done
rm -f t.mod t.out
. ../../testresult.sh
