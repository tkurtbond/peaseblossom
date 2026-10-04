#!/bin/sh
. ../../testenv.sh
# -strict is for the command line's module only, also when an import comes
# as a .sym: from a library (Out, poc-rtl's) or as a compiled module's .sym
# and .o (PLAN.md, "Ongoing bug fixing" 4: both were held to -strict); the
# module's own extensions are still reported.
exe=$(basename "$PWD")
rm -rf built
: >result
mkdir built
poc -output-dir built -compile lib/Wide.mod >/dev/null 2>&1
poc -strict -import-path built -o "$exe" -build client.mod >>result 2>&1
"./$exe" >>result 2>&1
poc -strict -import-path built -check client.mod >>result 2>&1
poc -strict -check own.mod >>result 2>&1
rm -rf built
. ../../testresult.sh
