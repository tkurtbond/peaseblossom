#!/bin/sh
. ../../testenv.sh
# Math and MathL where poc's differs from voc's or voc is wrong (denormals,
# succ/pred, bit-exact results, errors at the edges of the range, round's
# clamps), so poc only; llvm-math and llvm-mathl have the rest.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run mathextra.mod
. ../../testresult.sh
