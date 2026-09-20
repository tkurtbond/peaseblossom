#!/bin/sh
. ../../testenv.sh
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for triple in x86_64-unknown-linux-gnu i686-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir modulesmain.mod >/dev/null
  # main, up to its first call to a module body
  sed -n '/^define i32 @main/,/_init()/p' modulesmain.ll >>result
done
. ../../testresult.sh
