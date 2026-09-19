#!/bin/sh
. ../../testenv.sh
# Golden .ll diff of Phase 9 step 3's SET and character-array lowering at
# both target word sizes (the SET's own width follows the size model, not
# the word size, but the helper functions' i32 lengths and the GEPs into
# arrays are worth seeing at both), each also handed to clang for real.
# -target is pinned to fixed, host-independent triples, like every other
# -ir fixture.
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir setsstrings.mod >/dev/null
  cat setsstrings.ll >>result
  if clang -target $triple -c setsstrings.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
