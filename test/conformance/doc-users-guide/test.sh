#!/bin/sh
. ../../testenv.sh
# Phase 13 step 6: the User's Guide's examples. Each listing must be its
# file under doc/examples, and each shell session must give the output the
# guide shows (tools/guide-examples). Out comes from poc's own poc-rtl.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
root=../../..
rm -rf work
sh $root/tools/guide-examples check $root/doc/users-guide.md $root/doc/examples work >result 2>&1
echo "exit $?" >>result
rm -rf work
. ../../testresult.sh
