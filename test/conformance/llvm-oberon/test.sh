#!/bin/sh
. ../../testenv.sh
# oberon.mod under poc and voc, both size models, with the same arguments:
# the same output. beyond.mod, poc's alone: where poc's Oberon differs from
# voc's on purpose (an argument past 255 characters, the log's echo).
run_oberon() {
  "$1" Name.sub 12 '"a string"' -7 / x 2>&1
}
for model in -O2 -OC
do
  voc $model oberon.mod -m >/dev/null
  run_oberon ./oberon >"voc$model-output"
  rm -f *.c *.h *.o *.sym oberon
done
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for model in -O2 -OC
do
  echo "== oberon $model" >>result
  poc $model -o oberon.exe -build oberon.mod 2>&1 | grep -v '^semantic OK' >>result
  run_oberon ./oberon.exe >poc-output
  cat poc-output >>result
  cmp -s poc-output "voc$model-output" \
    || echo "poc and voc disagree under $model" >>result
done
long=$(printf '%0300d' 7)
for model in -O2 -OC
do
  echo "== beyond $model" >>result
  poc $model -o beyond.exe -build beyond.mod 2>&1 | grep -v '^semantic OK' >>result
  ./beyond.exe "$long" >>result 2>&1
  echo "exit=$?" >>result
done
rm -f poc-output voc-O2-output voc-OC-output *.sym
. ../../testresult.sh
