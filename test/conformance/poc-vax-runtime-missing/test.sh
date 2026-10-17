#!/bin/sh
. ../../testenv.sh
# The user, 2026-10-17: poc for Unix, asked for -target vax-dec-vms with
# no VAX runtime - no library POCRTL on the library path, no Out.Mod on
# the import path - says so once, and that the peaseblossom-vax package
# or make install-vax installs it (poc on VMS points to the kit's @BUILD
# instead). With rtl/vax's source on the import path it has a runtime,
# and a missing module of the program's own gets no such note.
# make check-install-vax checks the same with POCRTL installed.
: >result
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
run -target vax-dec-vms -clear-library-path -build Hello.mod
run -target vax-dec-vms -clear-library-path -build Lonely.mod
run -target vax-dec-vms -clear-library-path -import-path ../../../rtl/vax -build Lonely.mod
rm -f *.mar *.com
. ../../testresult.sh
