#!/bin/sh
. ../../testenv.sh
# -target pinned, as in llvm-straight-line-arithmetic
{
  echo "-O2:"
  poc -target x86_64-unknown-linux-gnu -emit-llvm-ir constir.mod
  cat constir.ll
  echo "-OC:"
  poc -OC -target x86_64-unknown-linux-gnu -emit-llvm-ir constir.mod
  cat constir.ll
} >result 2>&1
. ../../testresult.sh
