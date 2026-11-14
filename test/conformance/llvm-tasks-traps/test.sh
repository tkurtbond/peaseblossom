#!/bin/sh
. ../../testenv.sh
# Tasks (doc/developer/tasks.md, Phase 9): trap 19 (all tasks blocked:
# main alone, main joining a blocked task, a mutex, a condition); each case
# of 20 (Unlock of a mutex not held, by no one and by another task; Join
# of the running task; Send on a closed channel, and a sender waiting when
# its channel is closed; Close of a closed channel; Start of a started
# task; NewChannel with a negative capacity); 17 (a Yield in a finalizer
# and in a signal handler, with another task ready); each with a finalizer
# run.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# OpenBSD's ksh has no ulimit -v; there -d bounds anonymous mmap too.
limit_memory() {
  ulimit -v 1000000 2>/dev/null || ulimit -d 1000000
}
poc -o traps.exe -build traps.mod >result 2>&1
for which in 1 2 3 4 5 6 7 8 9 10 11 12 13 14
do
  echo "== $which" >>result
  (limit_memory; ./traps.exe $which) >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
rm -f *.sym traps.exe
. ../../testresult.sh
