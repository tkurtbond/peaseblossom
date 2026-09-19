#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 9 step 4a. Three checks, one golden file:
#  1. lib.sym is written with its hidden members (golden text).
#  2. Feeding that .sym back through poc as source and re-emitting it is a
#     no-op: the writer's own output is valid input and reaches a fixed
#     point (same technique as module-interface-real-roundtrip).
#  3. An importer's view of lib.ShapeDesc has the same size/alignment as
#     lib's own, for every word size and size model (-dump-layout prints
#     all four), even though the importer never saw a hidden field.
poc -emit-interface third.mod >/dev/null
poc -emit-interface lib.mod >/dev/null
cat lib.sym >result

mkdir -p again
cp third.sym again/
cp lib.sym again/lib.mod
(cd again && poc -emit-interface lib.mod >/dev/null)
if cmp -s lib.sym again/lib.sym
then echo "roundtrip: identical" >>result
else echo "roundtrip: DIFFERS" >>result; diff lib.sym again/lib.sym >>result
fi
rm -rf again

home=$(poc -dump-layout lib.mod | grep '^ShapeDesc:' | sed 's/^[A-Za-z]*: //')
seen=$(poc -dump-layout client.mod | grep '^View:' | sed 's/^[A-Za-z]*: //')
echo "lib.ShapeDesc: $home" >>result
echo "client.View:   $seen" >>result
if [ "$home" = "$seen" ]
then echo "layouts agree" >>result
else echo "layouts DIFFER" >>result
fi
. ../../testresult.sh
