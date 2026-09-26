#!/bin/sh
. ../../testenv.sh
# -target pinned to a fixed, host-independent triple, matching
# llvm-straight-line-arithmetic's own reasoning - this is a golden-file
# .ll diff, not a real toolchain invocation, so it must not depend on
# which host's clang auto-detection ran.
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir ctrl.mod >result 2>&1
cat ctrl.ll >>result
. ../../testresult.sh
