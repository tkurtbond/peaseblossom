#!/bin/sh
. ../../testenv.sh
# Phase 8 step 13 passed over semantic-expressions when promoting fixtures
# to compile+link+run: its REAL/SET/ARRAY-OF-CHAR expressions were all
# still Unsupported. Phase 9 steps 2-3 lowered them, so this is the
# promotion - but not a run: expressions.mod's VARs are never assigned,
# so "i DIV j" would divide by zero at run time. The check is instead
# that poc lowers every expression in it (the IR has no "; unsupported"
# marker, which is how any construct the backend cannot yet handle
# shows up) and that clang accepts the result. expressions.mod is a
# byte-for-byte copy of ../semantic-expressions/expressions.mod.
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir expressions.mod >/dev/null
echo "unsupported markers: $(grep -c '; unsupported' expressions.ll)" >result
if clang -target x86_64-unknown-linux-gnu -c expressions.ll -o /dev/null 2>clang.err
then echo "clang accepted" >>result
else echo "clang REJECTED" >>result; cat clang.err >>result
fi
rm -f clang.err
. ../../testresult.sh
