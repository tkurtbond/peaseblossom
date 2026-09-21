#!/bin/sh
. ../../testenv.sh
# The bit patterns must be the same under -O2 and -OC (poc's own source
# compiles under both, and this routine is part of it).
: >result
for model in -O2 -OC
do
  poc $model -emit-llvm-ir realbits.mod >/dev/null
  echo "$model" >>result
  grep 'store double 0x' realbits.ll | sed 's/.*double //; s/,.*//' >>result
done
. ../../testresult.sh
