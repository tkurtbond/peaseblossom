#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 12 step 5b: VT100. vt100same uses only what voc's VT100 does
# right, so poc and voc must write the same bytes under both size models;
# vt100diff is where poc's differs on purpose, poc's alone. Escape
# characters are shown by cat -v. voc runs first and its files go before
# poc starts: poc leaves .sym files in the working directory, which voc
# would find and reject as not its own.
for model in -O2 -OC
do
  voc $model vt100same.mod -m >/dev/null
  ./vt100same >"voc$model-output" 2>&1
  rm -f *.c *.h *.o *.sym vt100same
done
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model vt100same" >>result
  poc $model -o "$exe" -build vt100same.mod 2>&1 | grep -v '^semantic OK' >>result
  "./$exe" >poc-output 2>&1
  cat -v poc-output >>result
  cmp -s poc-output "voc$model-output" || echo "poc and voc disagree under $model" >>result
  echo "== $model vt100diff" >>result
  poc $model -o "$exe" -build vt100diff.mod 2>&1 | grep -v '^semantic OK' >>result
  "./$exe" | cat -v >>result
done
rm -f poc-output voc-O2-output voc-OC-output
. ../../testresult.sh
