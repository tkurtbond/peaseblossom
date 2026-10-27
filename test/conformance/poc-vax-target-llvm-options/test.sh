#!/bin/sh
. ../../testenv.sh
# The user, 2026-10-27: poc on Unix with -target vax-dec-vms refuses the
# options only the LLVM back end has, as poc on VMS does, since for the
# VAX they would do nothing: each option before the command and after
# the file, with -build, -compile and -library, and with -emit-macro32,
# -emit-vax-object and -emit-vax-image, which imply the target; and
# -dump-llvm-types and -emit-llvm-ir as commands. Nothing is written.
: >result
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
run -target vax-dec-vms -opt 1 -build Empty.mod
run -target vax-dec-vms -lto -build Empty.mod
run -target vax-dec-vms -rebuild -build Empty.mod
run -target vax-dec-vms -static -build Empty.mod
run -target vax-dec-vms -c-flag -g -build Empty.mod
run -target vax-dec-vms -verbose -build Empty.mod
run -build Empty.mod -target vax-dec-vms -lto
run -lto Empty.mod -target vax-dec-vms
run -target vax-dec-vms -verbose -compile Empty.mod
run -target vax-dec-vms -static -library Lib Empty.mod
run -opt 2 -emit-macro32 Empty.mod
run -emit-vax-object Empty.mod -lto
run -emit-vax-image -static Empty.mod
run -target vax-dec-vms -dump-llvm-types Empty.mod
run -target vax-dec-vms -emit-llvm-ir Empty.mod
echo "written: $(ls | grep -v -e '^Empty\.mod$' -e '^expected$' -e '^result$' -e '^test\.sh$' | LC_ALL=C sort | tr '\n' ' ')" >>result
. ../../testresult.sh
