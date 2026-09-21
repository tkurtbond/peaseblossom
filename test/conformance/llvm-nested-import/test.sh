#!/bin/sh
. ../../testenv.sh
# Tally's real source is found (and its .sym regenerated) by -build itself.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run client.mod
# The nested procedures are no part of the interface: Tally.sym has its three
# exported procedures and nothing more (said only when wrong, so `expected` stays
# the program's output, which llvm-i686-runtime also compares).
n=$(grep -c 'PROCEDURE' Tally.sym)
[ "$n" = 3 ] || echo "Tally.sym has $n procedures, not 3" >>result
grep -E 'Add|Loop|One|Many|Set' Tally.sym >/dev/null && echo "Tally.sym mentions a nested procedure" >>result
. ../../testresult.sh
