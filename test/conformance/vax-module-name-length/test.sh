#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 1: a module's initializer is <MODULE>_INIT, unhashed,
# so a module name is at most 26 characters (the design's section 5). Phase
# 16 step 4: -emit-macro32 refuses such a module, compiled itself or as an
# import, before its .sym is written, so that no file named after it is
# longer than ODS-2's 39 characters (section 15, proposal 3)
poc -dump-vax-names ABCDEFGHIJKLMNOPQRSTUVWXYZ.mod >result 2>&1
echo "exit $?" >>result
poc -dump-vax-names ABCDEFGHIJKLMNOPQRSTUVWXYZa.mod >>result 2>&1
echo "exit $?" >>result
rm -f *.sym *.mar
poc -emit-macro32 ABCDEFGHIJKLMNOPQRSTUVWXYZa.mod >>result 2>&1
echo "exit $?" >>result
poc -emit-macro32 LongNameImport.mod >>result 2>&1
echo "exit $?" >>result
ls *.sym *.mar >>result 2>/dev/null
rm -f *.sym *.mar
. ../../testresult.sh
