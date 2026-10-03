#!/bin/sh
. ../../testenv.sh
# Phase 13 step 7: the Reference Guide's chapter on the runtime modules must
# be what the modules of rtl/llvm say now: their header comments and their
# interfaces, each declaration with its comment (tools/rtl-reference). After
# changing a module, run tools/rtl-reference update.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
root=../../..
rm -rf work
sh $root/tools/rtl-reference check $root/doc/reference-guide.md $root/rtl/llvm work >result 2>&1
echo "exit $?" >>result
rm -rf work
. ../../testresult.sh
exit 0
