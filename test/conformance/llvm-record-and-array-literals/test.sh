#!/bin/sh
. ../../testenv.sh
# Phase 14: record and array literals and structured constants, three
# programs under both size models - then that a literal inside a loop has
# its stack slot in the entry block (no alloca after the function's first
# label), so the loop does not grow the stack.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  for program in records defaults edges
  do
    printf '== %s %s\n' "$model" "$program" >>result
    poc $model -o "$exe" -build $program.mod >>result 2>&1
    "./$exe" >>result 2>&1
  done
done
poc -emit-llvm-ir records.mod >>result 2>&1
awk '/^define .*@records.Loop\(/ { inside = 1; labels = 0; next }
     inside && /^}/ { inside = 0 }
     inside && /^[A-Za-z0-9_.]+:$/ && $0 != "entry:" { labels = 1 }
     inside && labels && /= alloca/ { print "alloca after a label: " $0 }' records.ll >>result
. ../../testresult.sh
