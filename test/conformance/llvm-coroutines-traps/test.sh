#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): trap 16 (a body
# returns); each case of 17 (a Transfer to a record never given to Init, to
# a freed coroutine, in a finalizer, in a signal handler; a Free of the
# running coroutine, of main's); 18 (Init refused its stack: MAX(LONGINT)
# bytes under a ulimit); and a NIL dereference, HALT and ASSERT on a
# coroutine; each with a finalizer run. With -trap-location too, which
# none of 16-18 carries.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# OpenBSD's ksh has no ulimit -v; there -d bounds anonymous mmap too.
limit_memory() {
  ulimit -v 1000000 2>/dev/null || ulimit -d 1000000
}
poc -o traps.exe -build traps.mod >result 2>&1
for which in 1 2 3 4 5 6 7 8 9 10 11 12
do
  echo "== $which" >>result
  (limit_memory; ./traps.exe $which) >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
echo "== -trap-location" >>result
poc -trap-location -o located.exe -build traps.mod >>result 2>&1
for which in 1 4 9
do
  (limit_memory; ./located.exe $which) >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
rm -f *.sym traps.exe located.exe
. ../../testresult.sh
