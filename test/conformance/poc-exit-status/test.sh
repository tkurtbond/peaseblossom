#!/bin/sh
. ../../testenv.sh
# poc's exit status: 0 when it did what it was asked, 1 when it reported an
# error of any kind. It used to be 0 always, so make and scripts could not tell
# a failed build from a good one. Only the status is recorded, not the
# messages, which other fixtures pin.
: >result
run() {
  poc "$@" >/dev/null 2>&1
  echo "exit $?: poc $*" >>result
}
run -check ok.mod
run -check-syntax ok.mod
run -dump-tokens ok.mod
run -emit-llvm-ir ok.mod
run -check typeerror.mod
run -check-syntax syntaxerror.mod
run -emit-interface typeerror.mod
run -emit-llvm-ir typeerror.mod
run -check missing.mod
run -emit-llvm-ir missing.mod
run -o prog -build ok.mod
run -o prog -build typeerror.mod
run -o prog -build vms.mod
run -o prog -build missing.mod
run -output-dir ok.mod/no-such-directory -emit-interface ok.mod
run -frobnicate ok.mod
run
run -print-import-path
[ -e prog ] && rm -f prog
# a failed run must not leave its half-written IR behind
ls -A | grep '^[.]tmp' >/dev/null && echo "LEFTOVER TEMP FILE" >>result
. ../../testresult.sh
