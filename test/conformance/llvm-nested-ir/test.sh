#!/bin/sh
. ../../testenv.sh
# Golden .ll of a procedure with nested ones at both target word sizes (each
# also handed to clang).
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir nestedir.mod >/dev/null
  cat nestedir.ll >>result
  if clang -target $triple -c nestedir.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
