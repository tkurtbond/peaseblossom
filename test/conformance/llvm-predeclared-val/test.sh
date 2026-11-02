#!/bin/sh
. ../../testenv.sh
# The predeclared VAL(T, x) on variables, every pair of families and widths
# that a check can tell apart, under both size models, as a line of: what is
# converted; its value without -range-checks, the bits SYSTEM.VAL gives, which
# the program compares; and with -range-checks, the same value, or status 14
# (doc/developer/language-extensions.md, "Predeclared unsigned types"). Then
# constants: VAL is one, wherever a constant goes, with no import.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
while read -r from value to print
do
  cat >val.mod <<MOD
MODULE val;
  IMPORT SYSTEM, Out;
  VAR x: $from; r: $to;
BEGIN
  x := $value;
  r := VAL($to, x);
  IF r # SYSTEM.VAL($to, x) THEN Out.String("differs from SYSTEM.VAL ") END;
  Out.$print(r, 0)
END val.
MOD
  for model in -O2 -OC
  do
    printf '%-4s VAL(%s, %s: %s):' "$model" "$to" "$value" "$from" >>result
    poc $model -o val.exe -build val.mod 2>&1 | grep -v '^semantic OK' >>result
    printf ' %s' "$(./val.exe 2>&1)" >>result
    poc $model -range-checks -o val.exe -build val.mod 2>&1 | grep -v '^semantic OK' >>result
    printf ' / %s' "$(./val.exe 2>&1)" >>result
    ./val.exe >/dev/null 2>&1
    printf ' (exit %d)\n' "$?" >>result
  done
done <cases.txt
for model in -O2 -OC
do
  echo "== constants $model" >>result
  poc $model -o constants.exe -build constants.mod 2>&1 | grep -v '^semantic OK' >>result
  ./constants.exe >>result
done
rm -f val.mod val.ll val.o val.sym val.exe
. ../../testresult.sh
