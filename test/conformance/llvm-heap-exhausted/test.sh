#!/bin/sh
. ../../testenv.sh
# Each case, chosen by the program's argument, built without and with
# -trap-heap-exhausted, under both size models; the output and exit status of
# each run are the expected text.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  for switch in "" -trap-heap-exhausted
  do
    poc $model $switch -o "$exe" -build heapexhausted.mod | grep -v '^semantic OK' >>result
    for case in 0 1 2 3
    do
      printf '== %s %s case %s\n' "$model" "${switch:-(default)}" "$case" >>result
      "./$exe" "$case" >>result 2>&1
      printf 'exit=%d\n' "$?" >>result
    done
  done
done
. ../../testresult.sh
