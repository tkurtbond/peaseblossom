#!/bin/sh
. ../../testenv.sh
# What the predeclared VAL(T, x) takes, one line per statement and model, "ok"
# if it is accepted (doc/developer/language-extensions.md, "Predeclared
# unsigned types"): integers of either family only; a constant that does not
# fit T is an error, whose T depends on the model. Then a program's own VAL,
# and what a module's own VAL or type name stops it writing to its .sym file.
: >result
while IFS= read -r stmt
do
  cat >t.mod <<MOD
MODULE t;
  CONST big = 0FFFFFFFFFFFFFFFFH;
  TYPE P = POINTER TO RECORD END;
  VAR sc: SHORTCARD; ca: CARDINAL; hc: HUGECARD; n: INTEGER; x: REAL; ch: CHAR; s: SET; p: P;
BEGIN
  $stmt
END t.
MOD
  for model in -O2 -OC
  do
    printf '%-4s %-36s ' "$model" "$stmt" >>result
    poc $model -check t.mod >t.out 2>&1
    if grep -q '^semantic OK' t.out
    then echo ok >>result
    else sed -n '1s/.*error: //p' t.out >>result
    fi
  done
done <statements.txt
rm -f t.mod exportedval.sym exportedval.ll exportedval.o
rm -f exportedtype.sym exportedtype.ll exportedtype.o
rm -f importedval.sym importedval.ll importedval.o
for program in ownval hiddenval exportedval exportedtype importedval
do
  echo "== $program" >>result
  poc -compile $program.mod >out 2>&1
  if grep -q 'error:' out
  then
    grep -v '^semantic OK' out >>result
    ls $program.* | LC_ALL=C sort >>result
  else cat $program.sym >>result
  fi
done
# Nothing is left of a module whose interface cannot be written, however it
# was reached, and an importer stops there too.
for command in "-emit-interface exportedval.mod" "-build exportedval.mod" "-compile usesexported.mod"
do
  echo "== poc $command" >>result
  poc $command >out 2>&1
  echo "exit $?" >>out
  grep -v '^semantic OK' out >>result
  ls exportedval* usesexported* | LC_ALL=C sort >>result
done
rm -f t.out out
. ../../testresult.sh
