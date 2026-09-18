#!/bin/sh
. ../../testenv.sh
# -target pinned to a fixed, host-independent triple, matching every
# other golden-file .ll diff fixture's own reasoning - this is a
# golden-file .ll diff, not a real toolchain invocation.
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir predeclaredir.mod >result
cat predeclaredir.ll >>result
. ../../testresult.sh
