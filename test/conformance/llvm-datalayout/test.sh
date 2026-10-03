#!/bin/sh
. ../../testenv.sh
# Each target's datalayout (LLVMTypes.DataLayout): x86_64, 32-bit x86 and
# aarch64 their own (aarch64 had x86_64's until Phase 13 step 4); an
# architecture poc has not been run on none, leaving it to clang.
for t in x86_64-unknown-linux-gnu x86_64-unknown-freebsd i386-unknown-openbsd \
         i686-pc-linux-gnu aarch64-unknown-freebsd riscv64-unknown-linux-gnu; do
  poc -target $t -emit-llvm-ir dl.mod >/dev/null 2>&1
  echo "$t: $(grep '^target datalayout' dl.ll || echo 'no datalayout line')"
done >result
rm -f dl.ll dl.sym
. ../../testresult.sh
