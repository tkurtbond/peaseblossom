#!/bin/sh
. ../../testenv.sh
# Golden .ll of the root table and its registration at both target word
# sizes (each also handed to clang), then, for a program that contains the
# collector itself, just the few lines of `main` that record the stack
# base - the collector's own IR is too big to golden here (llvm-gc-collect
# and llvm-gc-tracing run it).
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir roots.mod >/dev/null
  cat roots.ll >>result
  if clang -target $triple -c roots.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  poc -target $triple -emit-llvm-ir heapmain.mod >/dev/null
  grep 'stackbase\|frameaddress\|SetStackBase' heapmain.ll >>result
  if clang -target $triple -c heapmain.ll -o /dev/null 2>clang.err
  then echo "clang accepted heapmain $triple" >>result
  else echo "clang REJECTED heapmain $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
