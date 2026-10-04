#!/bin/sh
. ../../testenv.sh
# -check and -emit-interface judge a module by the target's word size, as a
# build does (PLAN.md, "Ongoing bug fixing" 2: -check used 32 bits whatever
# the host, and ignored -target). The host's own word size is the target
# without -target, which differs between the test hosts, so the targets
# here are explicit.
: >result
for target in x86_64-unknown-linux-gnu i686-unknown-linux-gnu
do
  printf '== %s\n' "$target" >>result
  poc -OC -target $target -check address.mod >>result 2>&1
  poc -OC -target $target -emit-interface address.mod >>result 2>&1
done
rm -f address.sym
. ../../testresult.sh
