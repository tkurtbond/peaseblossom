#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): a coroutine switches
# out of a C callback and is resumed before it returns to C (decision 8's
# rule); a pointer held only in a C frame of the suspended stack survives
# collections; the rounding mode (x87 control word and MXCSR, FPCR) stays
# with the coroutine that set it (decision 6).
POC_IMPORT_PATH=../../../rtl/llvm:part
export POC_IMPORT_PATH
poc_build_run callback.mod
rm -f *.sym part/*.sym part/*.o part/*.ll
. ../../testresult.sh
