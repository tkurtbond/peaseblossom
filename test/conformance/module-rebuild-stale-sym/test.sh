#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 9 step 4a: a stale .sym must never skew an importer's
# layout. lib.sym is emitted from libv1, then lib.mod is replaced by libv2
# (one more, hidden, 8-byte field) WITHOUT re-emitting it. The whole-program
# -emit-llvm-ir must regenerate lib.sym from lib.mod's real source, so
# client.View's descriptor (built from client's view of lib.sym) agrees
# with lib.ShapeDesc's (built from lib.mod itself). Run in a scratch
# subdirectory since lib.mod is swapped in place.
rm -rf work && mkdir work
cp client.mod work/
cp libv1.mod work/lib.mod
cd work
poc -emit-interface lib.mod >/dev/null
cp lib.sym lib.sym.v1
cp ../libv2.mod lib.mod
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir client.mod >/dev/null

: >../result
if cmp -s lib.sym lib.sym.v1
then echo "lib.sym: STALE (not regenerated)" >>../result
else echo "lib.sym: regenerated from source" >>../result
fi
awk '/^@(lib\.ShapeDesc|client\.View)\.tdesc = /{ name=$1; getline; getline; sub(/,/, "", $2); print name, "size", $2 }' client.ll >sizes
cat sizes >>../result
lib=$(grep '^@lib.ShapeDesc' sizes | cut -d' ' -f3)
view=$(grep '^@client.View' sizes | cut -d' ' -f3)
if [ "$lib" = "$view" ]
then echo "importer agrees with lib's own source" >>../result
else echo "importer DISAGREES with lib's own source" >>../result
fi
cd ..
rm -rf work
. ../../testresult.sh
