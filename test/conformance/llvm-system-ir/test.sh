#!/bin/sh
. ../../testenv.sh
# Golden .ll of llvm-system's own program (the SYSTEM subset: ADR/GET/PUT/
# VAL/MOVE) at both target word sizes, where SYSTEM.ADDRESS is i32 and i64
# respectively, each also handed to clang for real. The program itself is
# llvm-system's, not copied.
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir ../llvm-system/system.mod >/dev/null
  cat system.ll >>result
  if clang -target $triple -c system.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
