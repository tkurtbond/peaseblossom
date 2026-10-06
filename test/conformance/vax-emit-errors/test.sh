#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 steps 2-3 (doc/developer/vax-macro32-backend.md, sections
# 5 and 10): what -emit-macro32 and -target vax-dec-vms refuse, each with
# exit status 1 and nothing written
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
  ls *.mar *.ll 2>/dev/null | sed 's/^/written: /' >>result
}
: >result
run -emit-macro32 VaxTooMuch.mod
run -emit-macro32 VaxNameClash.mod
run -target x86_64-unknown-linux-gnu -emit-macro32 VaxEmpty.mod
run -OC -emit-macro32 VaxEmpty.mod
run -target vax-dec-vms -emit-llvm-ir VaxEmpty.mod
run -target vax-dec-vms -build VaxEmpty.mod
run -target vax-dec-vms VaxEmpty.mod
run -target vax-dec-vms -compile VaxEmpty.mod
run -target vax-dec-vms -library vaxlib VaxEmpty.mod
. ../../testresult.sh
