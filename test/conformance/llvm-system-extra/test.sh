#!/bin/sh
. ../../testenv.sh
# SYSTEM where poc's differs from voc's or voc leaves it undefined (counts of
# the width or more, CHAR and BYTE operands, bit numbers beyond a word, PTR
# comparisons, SYSTEM.NEW blocks, the fixed-width names): poc only;
# llvm-system-shifts and llvm-system-bytes have the rest.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run systemextra.mod
. ../../testresult.sh
