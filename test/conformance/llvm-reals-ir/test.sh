#!/bin/sh
. ../../testenv.sh
# Golden .ll diff of PLAN.md Phase 9 step 2's REAL/LONGREAL lowering at
# both target word sizes, each also handed to clang for real: a golden
# file only proves the text is what poc used to print, and floating-point
# constants are exactly where LLVM's own parser is strictest (see
# realsir.mod). -target is pinned to fixed, host-independent triples,
# like every other -ir fixture.
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir realsir.mod >/dev/null
  cat realsir.ll >>result
  if clang -target $triple -c realsir.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
