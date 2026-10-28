#!/bin/sh
. ../../testenv.sh
# doc/developer/vax-macro32-backend.md, section 13.1, proposal 5: poc
# -target vax-dec-vms -build takes object files, .obj files in any case
# after the program's file, each in the counted form poc's own objects
# have here. Each is copied beside the modules' files, and the procedure
# converts it by OBJCONVERT and lists it after the modules' objects and
# the command tables', whether the modules are MACRO-32 or objects; the
# procedures are compared with expected-Use.com and
# expected-Use-objects.com. Then what is refused, each with exit status 1:
# an object whose name is a module's, a command table's object's, another
# object's or the runtime's, a name VMS cannot have, an object that is not
# there, one not in the counted form (a text file, an empty file, one
# with its counts lost, as FTP in binary leaves an object from VMS, and
# one with a record of 514 bytes, longer than OBJCONVERT takes), and
# an object given to any other command or target.
rm -rf work
mkdir work work/other
run() {
  echo "== poc $*" >>result
  (cd work && poc "$@") >>result 2>&1
  echo "exit $?" >>result
}
compare() {
  if diff "$1" "work/$2" >work/diff 2>&1; then
    echo "$2 matches $1" >>result
  else
    echo "$2 differs from $1:" >>result; cat work/diff >>result
  fi
}
: >result
cp Use.mod Helper.mod Table.cld work/
printf 'not an object\n' >work/Text.obj
(cd work && poc -target vax-dec-vms -emit-vax-object Helper.mod) >>result 2>&1
mv work/Helper.obj work/other/Twice.obj
cp work/other/Twice.obj work/other/OTHER.OBJ
cp work/other/Twice.obj work/Use.obj
cp work/other/Twice.obj work/Table.obj
cp work/other/Twice.obj work/TWICE.obj
cp work/other/Twice.obj work/POCRTL.obj
cp work/other/Twice.obj work/bad.name.obj
: >work/Empty.obj
tail -c +3 work/other/Twice.obj >work/Ftp.obj
{ printf '\002\002'; head -c 514 /dev/zero; } >work/Long.obj
run -target vax-dec-vms -build Use.mod other/Twice.obj other/OTHER.OBJ
compare expected-Use.com Use.com
cmp -s work/other/Twice.obj work/Twice.obj && echo "other/Twice.obj copied to Twice.obj" >>result
cmp -s work/other/OTHER.OBJ work/OTHER.obj && echo "other/OTHER.OBJ copied to OTHER.obj" >>result
rm -f work/Use.com work/Twice.obj work/OTHER.obj
run -target vax-dec-vms -vax-objects -build Use.mod Table.cld other/Twice.obj
compare expected-Use-objects.com Use.com
rm -f work/Use.com
run -target vax-dec-vms -build Use.mod Use.obj
run -target vax-dec-vms -build Use.mod Table.cld Table.obj
run -target vax-dec-vms -build Use.mod other/Twice.obj TWICE.obj
run -target vax-dec-vms -build Use.mod POCRTL.obj
run -target vax-dec-vms -build Use.mod bad.name.obj
run -target vax-dec-vms -build Use.mod missing.obj
run -target vax-dec-vms -build Use.mod Text.obj
run -target vax-dec-vms -build Use.mod Empty.obj
run -target vax-dec-vms -build Use.mod Ftp.obj
run -target vax-dec-vms -build Use.mod Long.obj
run -build Use.mod other/Twice.obj
run Use.mod other/Twice.obj
run -target vax-dec-vms -emit-macro32 Use.mod other/Twice.obj
run -target vax-dec-vms -compile Use.mod other/Twice.obj
run -target vax-dec-vms -library USE Use.mod other/Twice.obj
ls work/*.com 2>/dev/null | LC_ALL=C sort | sed 's/^/procedure: /' >>result
rm -rf work
. ../../testresult.sh
