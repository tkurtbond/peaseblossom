#!/bin/sh
. ../../testenv.sh
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
# Doesn't reuse poc_build_run: the exit status matters here (see
# llvm-predeclared-halt/test.sh). The fatal error names the file by its
# absolute path, which differs from one machine to the next, so it is
# shown as "<cwd>".
# The message goes to standard error (Phase 11 D12), the program's own
# output to standard output: each is shown under its own heading.
poc -o llvm-files-fail -build filesfail.mod >result 2>&1
echo "standard output:" >>result
./llvm-files-fail 2>/dev/null >>result
echo "standard error:" >>result
./llvm-files-fail 2>&1 >/dev/null | sed "s|$PWD|<cwd>|" >>result
printf 'exit=%d\n' "$(./llvm-files-fail >/dev/null 2>&1; echo $?)" >>result
. ../../testresult.sh
