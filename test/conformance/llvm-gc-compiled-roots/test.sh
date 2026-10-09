#!/bin/sh
. ../../testenv.sh
# A module with a pointer among its module-level VARs, compiled by
# -compile alone (G imports nothing, so it brings no runtime), has its
# root table all the same, registered through a weak reference to
# ModuleTable.Register, called when it is not null:
#   1. G.o refers to ModuleTable.Register weakly;
#   2. given as its .sym and .o to a program that has the collector, what
#      G.p reaches survives a collection - until 2026-10-08 G had no root
#      table there, and G.p's record was freed and its memory used again
#      (Phase 15's "Ongoing bug fixing" 6);
#   3. a program without NEW, or a library module (which brings the
#      collector), links none of ModuleTable, and runs.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
# a symbol and its nm type, a weak one's "weak": OpenBSD's nm says W where
# GNU's and LLVM's say w
symbols() { awk '{ if ($2 ~ /^[wWvV]$/) print $1, "weak"; else print $1, $2 }'; }
rm -rf work && mkdir -p work/pair work/use work/plain
cp src/G.Mod work/pair/ && cp src/M.Mod work/use/ && cp src/N.Mod work/plain/
: >result
echo "== 1." >>result
(cd work/pair && poc -compile G.Mod 2>&1 && rm G.Mod G.ll) >>result
nm -P work/pair/G.o | grep '^ModuleTable\.' | symbols >>result
echo "== 2." >>result
(cd work/use && poc -import-path ../pair -o m -build M.Mod 2>&1 && ./m) >>result
echo "== 3." >>result
(cd work/plain && poc -import-path ../pair -o n -build N.Mod 2>&1 && ./n && echo "ran" \
  && nm -P n | grep '^ModuleTable\.' | symbols) >>result
rm -rf work
. ../../testresult.sh
