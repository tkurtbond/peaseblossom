#!/bin/sh
. ../../testenv.sh
# Tasks (doc/developer/tasks.md, Phase 9): start, run, join, the run
# queue's order, Yield, a task's stack given back after it returns (many
# short tasks under a memory limit). Under both size models.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# OpenBSD's ksh has no ulimit -v; there -d bounds anonymous mmap too.
limit_memory() {
  ulimit -v 1000000 2>/dev/null || ulimit -d 1000000
}
poc -o llvm-tasks -build tasks.mod >result 2>&1
(limit_memory; ./llvm-tasks) >>result 2>&1
printf 'exit=%d\n' "$?" >>result
echo "== -OC" >>result
poc -OC -o llvm-tasks-oc -build tasks.mod >>result 2>&1
(limit_memory; ./llvm-tasks-oc) >>result 2>&1
printf 'exit=%d\n' "$?" >>result
rm -f *.sym llvm-tasks-oc
. ../../testresult.sh
