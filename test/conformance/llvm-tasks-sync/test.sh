#!/bin/sh
. ../../testenv.sh
# Tasks (doc/developer/tasks.md, Phase 9): conditions (Mesa's rule),
# Signal and Broadcast, a mutex held across a Send. Under both size models.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run sync.mod
echo "== -OC" >>result
poc -OC -o llvm-tasks-sync-oc -build sync.mod >>result 2>&1
./llvm-tasks-sync-oc >>result 2>&1
printf 'exit=%d\n' "$?" >>result
rm -f *.sym llvm-tasks-sync-oc
. ../../testresult.sh
