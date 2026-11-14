#!/bin/sh
. ../../testenv.sh
# Tasks (doc/developer/tasks.md, Phase 9): channels unbuffered and
# buffered, Close, Receive's FALSE, NIL as a message, TrySend and
# TryReceive, Select, Go's concurrent prime sieve. Under both size models.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run channels.mod
echo "== -OC" >>result
poc -OC -o llvm-tasks-channels-oc -build channels.mod >>result 2>&1
./llvm-tasks-channels-oc >>result 2>&1
printf 'exit=%d\n' "$?" >>result
rm -f *.sym llvm-tasks-channels-oc
. ../../testresult.sh
