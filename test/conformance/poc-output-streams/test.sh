#!/bin/sh
. ../../testenv.sh
# Which of poc's two streams each kind of output goes to (Phase 11 D11), as
# gcc and clang do: errors, error counts, failures and the usage text on
# standard error; on standard output only what the command was asked for (a
# dump, an interface, the import path, "syntax OK"/"semantic OK"). Each line
# gives the exit status and how many lines went to each stream; the messages
# themselves are pinned by other fixtures.
: >result
run() {
  poc "$@" >stdout.txt 2>stderr.txt
  status=$?
  echo "exit $status, stdout $(wc -l <stdout.txt | tr -d ' '), stderr $(wc -l <stderr.txt | tr -d ' '): poc $*" >>result
}
run -check ok.mod
run -check-syntax ok.mod
run -dump-tokens ok.mod
run -show-interface ok.mod
run -emit-llvm-ir ok.mod
run -check typeerror.mod
run -check-syntax syntaxerror.mod
run -dump-tokens badtoken.mod
run -emit-interface typeerror.mod
run -emit-llvm-ir typeerror.mod
run -check missing.mod
run -o prog -build vms.mod
# Phase 13 step 2: silent on success, with or without -build; the
# executable is named after the module
run -build ok.mod
run ok.mod
run -output-dir ok.mod/no-such-directory -emit-interface ok.mod
run -frobnicate ok.mod
run
# Phase 13 step 1: the version, the target and size model, and clang's version
run -version
# Phase 13 step 2, and 2026-10-05: every command and option, on standard output
run -help
run -print-import-path
rm -f stdout.txt stderr.txt prog ok ok.o ok.ll ok.sym
. ../../testresult.sh
