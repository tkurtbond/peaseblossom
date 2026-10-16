#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vax-macro32-backend.md, section 23,
# proposal 5): poc -target vax-dec-vms -build takes command tables, .cld
# files after the program's file, in any case. Each is copied beside the
# .mar files, and the procedure compiles it by SET COMMAND/OBJECT and lists
# its object after the modules'; the procedure is compared with
# expected-Tables.com. Then what is refused, each with exit status 1: a
# table whose object would be a module's, a name VMS cannot have, a table
# that is not there, and a table given to any other command or target.
# vax-cli-table builds and runs such a program on the guest.
rm -rf work
mkdir work
run() {
  echo "== poc $*" >>result
  (cd work && poc "$@") >>result 2>&1
  echo "exit $?" >>result
}
: >result
cp Tables.mod One.cld Two.CLD Tables.cld bad.name.cld work/
run -target vax-dec-vms -build Tables.mod One.cld Two.CLD
if diff expected-Tables.com work/Tables.com >work/diff 2>&1; then
  echo "Tables.com matches expected-Tables.com" >>result
else
  echo "Tables.com differs from expected-Tables.com:" >>result; cat work/diff >>result
fi
cmp -s One.cld work/One.cld && echo "One.cld copied to One.cld" >>result
cmp -s Two.CLD work/Two.cld && echo "Two.CLD copied to Two.cld" >>result
rm -f work/Tables.com
run -target vax-dec-vms -build Tables.mod Tables.cld
run -target vax-dec-vms -build Tables.mod bad.name.cld
run -target vax-dec-vms -build Tables.mod missing.cld
run -build Tables.mod One.cld
run Tables.mod One.cld
run -target vax-dec-vms -emit-macro32 Tables.mod One.cld
run -target vax-dec-vms -compile Tables.mod One.cld
run -target vax-dec-vms -library TABLES Tables.mod One.cld
ls work/*.com 2>/dev/null | sed 's/^/procedure: /' >>result
rm -rf work
. ../../testresult.sh
