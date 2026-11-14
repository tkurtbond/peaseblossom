#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): the call-frame
# information of the trampoline that starts a coroutine marks its return
# address undefined, so that a debugger's backtrace ends there
# (concurrency-survey.md, 8.7.2). Coroutines.c's object has one
# DW_CFA_undefined, the trampoline's; its other functions have none.
# FreeBSD's readelf (LLVM's) cannot dump frames, nor OpenBSD's objdump.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
rm -rf work && mkdir work && cd work || exit 1
poc -compile ../../../../rtl/llvm/Coroutines.Mod >../result 2>&1
frames() {
  readelf --debug-dump=frames "$1" 2>/dev/null ||
    objdump --dwarf=frames "$1" 2>/dev/null
}
printf 'DW_CFA_undefined: %d\n' "$(frames Coroutines.c.o | grep -c DW_CFA_undefined)" >>../result
cd ..
rm -rf work
. ../../testresult.sh
