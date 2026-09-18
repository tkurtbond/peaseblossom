#!/bin/sh
. ../../testenv.sh
# -target pinned to a fixed, host-independent triple so this golden file
# doesn't depend on which host's clang auto-detection ran (see
# llvm-build-run, which does rely on real auto-detection/toolchain
# invocation and so cannot be a golden-diff fixture the same way).
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir stub.mod >result
cat llvmStub.ll >>result
. ../../testresult.sh
