#!/bin/sh
. ../../testenv.sh
# Golden .ll diff of every run-time type descriptor (PLAN.md Phase 9
# step 1) at both target word sizes, each also handed to clang for real:
# a golden file only proves the text is what poc used to print, not that
# it is valid LLVM IR - the descriptor initializers (self-referential
# aliases, [0 x T] tables, constant-expression GEPs) are exactly the kind
# of thing a plausible-looking text can get subtly wrong. -target is
# pinned to fixed, host-independent triples, like every other -ir fixture.
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir typedesc.mod >/dev/null
  cat typedesc.ll >>result
  if clang -target $triple -c typedesc.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
