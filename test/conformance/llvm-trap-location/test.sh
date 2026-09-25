#!/bin/sh
. ../../testenv.sh
# Each case, chosen by the program's argument, under both size models, built
# with -trap-location (and -trap-heap-exhausted, for case 10's heap trap);
# then case 0 once without the switch, where the message has no location.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  poc $model -import-path lib -trap-location -trap-heap-exhausted -o "$exe" -build traplocation.mod \
    | grep -v '^semantic OK' >>result
  for case in 0 1 2 3 4 5 6 7 8 9 10
  do
    printf '== %s case %s\n' "$model" "$case" >>result
    "./$exe" "$case" >>result 2>&1
    printf 'exit=%d\n' "$?" >>result
  done
done
poc -import-path lib -o "$exe" -build traplocation.mod | grep -v '^semantic OK' >>result
printf '== without -trap-location, case 0\n' >>result
"./$exe" 0 >>result 2>&1
printf 'exit=%d\n' "$?" >>result
. ../../testresult.sh
