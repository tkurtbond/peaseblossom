#!/bin/sh
. ../../testenv.sh
# reals.mod under poc and voc, both size models: the same output.
# beyond.mod, poc's alone: where poc's Reals differs from voc's on purpose
# (TenL correctly rounded, negative exponents, ConvertL past LONGINT).
for model in -O2 -OC
do
  voc $model reals.mod -m >/dev/null
  ./reals >"voc$model-output" 2>&1
  rm -f *.c *.h *.o *.sym reals
done
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for model in -O2 -OC
do
  echo "== reals $model" >>result
  poc $model -o reals.exe -build reals.mod 2>&1 | grep -v '^semantic OK' >>result
  ./reals.exe >poc-output 2>&1
  cmp -s poc-output "voc$model-output" \
    || echo "poc and voc disagree under $model" >>result
done
for model in -O2 -OC
do
  echo "== beyond $model" >>result
  poc $model -o beyond.exe -build beyond.mod 2>&1 | grep -v '^semantic OK' >>result
  ./beyond.exe >>result 2>&1
  echo "exit=$?" >>result
done
rm -f poc-output voc-O2-output voc-OC-output *.sym
. ../../testresult.sh
