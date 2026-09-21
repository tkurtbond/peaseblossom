#!/bin/sh
. ../../testenv.sh
# Phase 11 step 2 (inventory A9): where SYSTEM.ADDRESS sits among the
# integers depends on the target's word size, as SYSTEM.INTn's place does on
# the size model. For each (word size, size model): which integer types are
# assignable to an ADDRESS ("to"), which an ADDRESS is assignable to
# ("from"), and the type of a mixed sum "a + x" (its narrowest assignable
# type among ADDRESS/HUGEINT, ADDRESS first). A LONGINT is wider than a
# 32-bit ADDRESS only under -OC, and then is not assignable to it; a 64-bit
# ADDRESS is as wide as HUGEINT and includes each other with it, and (under
# -OC, where LONGINT is 8 bytes too) includes LONGINT, which still ranks below
# HUGEINT, without being included by it.
: >result
for target in i686-unknown-linux-gnu x86_64-unknown-linux-gnu
do
  for model in -O2 -OC
  do
    echo "### $target $model" >>result
    for t in SHORTINT INTEGER LONGINT HUGEINT
    do
      to=no; from=no; sum=-
      printf 'MODULE P;\n  IMPORT SYSTEM;\n  VAR a: SYSTEM.ADDRESS; x: %s;\nBEGIN\n  a := x\nEND P.\n' "$t" >P.mod
      poc -target $target $model -emit-llvm-ir P.mod >/dev/null 2>&1 && to=yes
      printf 'MODULE P;\n  IMPORT SYSTEM;\n  VAR a: SYSTEM.ADDRESS; x: %s;\nBEGIN\n  x := a\nEND P.\n' "$t" >P.mod
      poc -target $target $model -emit-llvm-ir P.mod >/dev/null 2>&1 && from=yes
      printf 'MODULE P;\n  IMPORT SYSTEM;\n  VAR a, r: SYSTEM.ADDRESS; x: %s;\nBEGIN\n  r := a + x\nEND P.\n' "$t" >P.mod
      poc -target $target $model -emit-llvm-ir P.mod >/dev/null 2>&1 && sum=ADDRESS
      [ $sum = - ] && { printf 'MODULE P;\n  IMPORT SYSTEM;\n  VAR a: SYSTEM.ADDRESS; x: %s; r: HUGEINT;\nBEGIN\n  r := a + x\nEND P.\n' "$t" >P.mod
        poc -target $target $model -emit-llvm-ir P.mod >/dev/null 2>&1 && sum=wider; }
      printf '  %-9s to ADDRESS: %-3s  from ADDRESS: %-3s  a + x: %s\n' "$t" $to $from $sum >>result
    done
  done
done
rm -f P.mod P.ll P.sym
. ../../testresult.sh
