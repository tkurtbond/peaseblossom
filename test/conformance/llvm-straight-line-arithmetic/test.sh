#!/bin/sh
. ../../testenv.sh
# -target pinned to a fixed, host-independent triple, matching
# llvm-emit-ir's own reasoning - this is a golden-file .ll diff, not a
# real toolchain invocation, so it must not depend on which host's
# clang auto-detection ran.
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir arith.mod >result
cat arith.ll >>result
. ../../testresult.sh
