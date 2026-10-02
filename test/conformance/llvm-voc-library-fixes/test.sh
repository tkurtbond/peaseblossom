#!/bin/sh
. ../../testenv.sh
# libraryfixes under poc and voc, both size models: the same output. voc runs
# first and its files go before poc starts (poc's .sym files are not voc's).
for model in -O2 -OC
do
  voc $model Ro.Mod libraryfixes.mod -m >/dev/null
  ./libraryfixes >"voc$model-output" 2>&1
  rm -f *.c *.h *.o *.sym libraryfixes
done
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -emit-interface Ro.Mod >/dev/null
  poc $model -o "$exe" -build libraryfixes.mod 2>&1 | grep -v '^semantic OK' >>result
  "./$exe" >poc-output 2>&1
  cat poc-output >>result
  cmp -s poc-output "voc$model-output" || echo "poc and voc disagree under $model" >>result
  rm -f *.sym
done
rm -f poc-output voc-O2-output voc-OC-output
. ../../testresult.sh
