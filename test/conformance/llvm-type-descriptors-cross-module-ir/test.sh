#!/bin/sh
. ../../testenv.sh
# client.mod imports shapes.mod; shapes.sym is what client's own
# CheckModule resolves the import through, while the whole-program .ll
# (one shapes descriptor, one client descriptor referencing it) is built
# from both modules' real source - same arrangement as llvm-multi-module.
triple=x86_64-unknown-linux-gnu
poc -emit-interface shapes.mod >/dev/null
poc -target $triple -emit-llvm-ir client.mod >/dev/null
# one .ll per module (Phase 12 step 2a): shapes.ll defines the descriptor,
# client.ll declares what it uses of it
: >result
for m in shapes client; do
  echo "== $m.ll" >>result
  cat $m.ll >>result
  if clang -target $triple -c $m.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
done
rm -f clang.err
. ../../testresult.sh
