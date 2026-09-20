#!/bin/sh
. ../../testenv.sh
# The declare line of every external procedure of externs.mod (each also
# handed to clang for real), under both size models at both word sizes.
: >result
for model in -O2 -OC; do
  for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
    echo "== $model $triple" >>result
    poc $model -target $triple -emit-llvm-ir externs.mod >/dev/null
    grep '^declare .*@ext' externs.ll >>result
    if clang -target $triple -c externs.ll -o /dev/null 2>clang.err
    then echo "clang accepted" >>result
    else echo "clang REJECTED" >>result; cat clang.err >>result
    fi
    rm -f clang.err
  done
done
. ../../testresult.sh
