#!/bin/sh
. ../../testenv.sh
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# Doesn't reuse poc_build_run: the exit status matters here (see
# llvm-predeclared-halt/test.sh). The fatal error names the file by its
# absolute path, which differs from one machine to the next, so it is
# shown as "<cwd>".
poc -o llvm-files-fail -build filesfail.mod >result
./llvm-files-fail 2>&1 | sed "s|$PWD|<cwd>|" >>result
printf 'exit=%d\n' "$(./llvm-files-fail >/dev/null 2>&1; echo $?)" >>result
. ../../testresult.sh
