#!/bin/sh
. ../../testenv.sh
# Record field initializers (Phase 11 D17): the program's output, then the
# .sym file of the imported module, which says which fields have one
# (":= ..") but not what it is.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run fielduse.mod
cat FieldLib.sym >>result
. ../../testresult.sh
