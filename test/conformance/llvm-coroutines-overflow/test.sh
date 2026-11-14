#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): a stack does not grow,
# and a recursion past its end runs into the guard page below it: SIGSEGV
# (11 everywhere), or SIGBUS (7 on Linux, 10 on the BSDs), which a BSD may
# give; not another stack's memory or the heap's. The shell's status for a
# signal is 128 + its number.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# OpenBSD's ksh has no ulimit -v; there -d bounds anonymous mmap too.
limit_memory() {
  ulimit -v 1000000 2>/dev/null || ulimit -d 1000000
}
poc -o overflow.exe -build overflow.mod >result 2>&1
(ulimit -c 0; limit_memory; ./overflow.exe >>result) 2>/dev/null
status=$?
case $status in
  139|135|138) echo "killed by SIGSEGV or SIGBUS" >>result ;;
  *) printf 'exit=%d\n' "$status" >>result ;;
esac
rm -f *.sym overflow.exe
. ../../testresult.sh
