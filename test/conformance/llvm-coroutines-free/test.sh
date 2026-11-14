#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): Free gives back a
# stack, so that Init can make more of them than the address space the
# ulimit allows would hold; Free's no-op cases; and the Transfer to a freed
# coroutine that traps (17).
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# OpenBSD's ksh has no ulimit -v; there -d bounds anonymous mmap too.
limit_memory() {
  ulimit -v 1000000 2>/dev/null || ulimit -d 1000000
}
poc -o free.exe -build free.mod >result 2>&1
(limit_memory; ./free.exe) >>result 2>&1
printf 'exit=%d\n' "$?" >>result
rm -f *.sym free.exe
. ../../testresult.sh
