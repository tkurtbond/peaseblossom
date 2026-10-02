#!/bin/sh
. ../../testenv.sh
# Phase 12 step 2c: libraries. rtl/llvm is built into the library poc-rtl,
# then src/ into shapes on top of it; main links both, statically and then
# as shared libraries (run from another directory too: the run-time search
# path is absolute). Then what poc refuses: a module that a library on the
# path has already, an import that is neither a file of the library nor in a
# library, a module two linked libraries both have, and a library compiled
# against an interface of Out that the poc-rtl on the path no longer has.
# The import path is empty throughout, so every module the programs import
# can only come from a library; -clear-library-path keeps poc's own
# lib/poc out. The host's triple and the keys are masked.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(clang -dumpmachine)
mask() {
  sed -e "s|$triple|<triple>|g" -e 's/[0-9a-f]\{16\}/<key>/g' -e 's/libpoc-rtl\.so\.0\.0/libpoc-rtl.so/' \
      -e 's/libshapes\.so\.0\.0/libshapes.so/'
}
poc() { command poc -clear-library-path "$@"; }
rm -rf work && mkdir work && cd work
: >../result
echo "== poc-rtl and shapes" >>../result
poc -output-dir lib -library poc-rtl ../../../../rtl/llvm/*.Mod 2>&1 | mask >>../result
poc -library-path lib -output-dir lib -library shapes ../src/Lists.Mod ../src/Stacks.Mod 2>&1 | mask >>../result
mask <lib/$triple/O2/shapes.library >>../result
ls lib/$triple/O2 | grep -e '^lib' -e 'Lists\.' | mask | LC_ALL=C sort >>../result
echo "== static" >>../result
poc -library-path lib -o main -build ../main.mod 2>&1 | mask >>../result
./main >>../result
echo "== shared" >>../result
poc -library-path lib -shared-libraries -o mains -build ../main.mod 2>&1 | mask >>../result
./mains >>../result
here=$PWD
(cd / && "$here/mains") >>../result
echo "== a module a library on the path has" >>../result
poc -library-path lib -output-dir lib2 -library other ../src/Lists.Mod 2>&1 | mask >>../result
echo "== an import from neither" >>../result
# Helper.Mod is on the import path, but a library is made of its files only
poc -import-path .. -library-path lib -output-dir lib2 -library extra ../src/Extra.Mod 2>&1 | mask >>../result
echo "== one module in two libraries" >>../result
# dup has Lists too, built against a copy of the path without shapes
cp -r lib lib4 && rm -f lib4/$triple/O2/Lists.* lib4/$triple/O2/Stacks.* lib4/$triple/O2/*shapes*
poc -library-path lib4 -output-dir lib3 -library dup ../src/Lists.Mod ../dup/Queues.Mod 2>&1 | mask >>../result
poc -library-path lib -library-path lib3 -o main2 -build ../main2.mod >out 2>&1
echo "exit=$?" >>../result
mask <out >>../result
echo "== shapes against an older Out" >>../result
# poc-rtl rebuilt, in a copy, from an Out with one more procedure
cp -r lib libstale && mkdir rtl && cp ../../../../rtl/llvm/*.Mod ../../../../rtl/llvm/*.c rtl/
awk 'NR == 104 { print "  PROCEDURE Extra*;"; print "  END Extra;"; print "" } { print }' ../../../../rtl/llvm/Out.Mod >rtl/Out.Mod
poc -library-path libstale -output-dir libstale -library poc-rtl rtl/*.Mod 2>&1 | mask >>../result
poc -library-path libstale -o main -build ../main.mod 2>&1 | mask >>../result
cd ..
rm -rf work
. ../../testresult.sh
