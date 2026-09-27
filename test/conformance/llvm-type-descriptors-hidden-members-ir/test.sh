#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 9 step 4a, the descriptor half. client.CircleDesc and
# client.View extend lib.ShapeDesc, whose hidden fields (weight, inner,
# stamp) and hidden procedure (Audit) client's own view of lib.sym now
# includes. In the golden below, read: lib.ShapeDesc's size and pointer
# offsets (8, 24 on x86_64 - inner is hidden), then client.View's, which
# must repeat them exactly (View adds nothing), and client.CircleDesc's,
# whose own fields must start at ShapeDesc's size and whose ProcTab keeps
# lib's hidden Audit in slot 1 while its own same-named Audit gets a new
# slot. Each is also handed to clang -c, like llvm-type-descriptors-ir.
# No .sym is emitted by hand: the whole-program commands regenerate lib's
# and third's own (step 4a's driver change).
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir client.mod >/dev/null
  # one .ll per module (Phase 12 step 2a)
  for m in third lib client; do
    echo "-- $m.ll" >>result
    cat $m.ll >>result
    if clang -target $triple -c $m.ll -o /dev/null 2>clang.err
    then echo "clang accepted $triple" >>result
    else echo "clang REJECTED $triple" >>result; cat clang.err >>result
    fi
  done
  rm -f clang.err
done
. ../../testresult.sh
