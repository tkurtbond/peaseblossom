#!/bin/sh
. ../../testenv.sh
# figures' real source is found (and its .sym regenerated) by -build
# itself, as for llvm-multi-module; the runtime through the import path.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run client.mod
. ../../testresult.sh
