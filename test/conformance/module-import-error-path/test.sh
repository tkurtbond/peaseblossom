#!/bin/sh
. ../../testenv.sh
# A compile-time error in an imported module names the file poc read: a .Mod
# found through -import-path with its directory, one in the current directory
# as it is (it used to be the constructed Bad.mod in both cases).
: >result
poc -import-path lib -emit-llvm-ir topbad.mod >>result 2>&1
poc -emit-llvm-ir toplow.mod >>result 2>&1
# "Ongoing bug fixing" 17 in PLAN.md: a file named on the command line is not
# an imported module, even when another file named there imports it (the
# VAX's -compile is in vax-module-name-length, which check-opt2 leaves out).
for command in "-compile low.mod" "-compile toplow.mod" "-compile toplow.mod low.mod" \
    "-output-dir lib -library lowlib low.mod"
do
  echo "== poc $command" >>result
  poc $command >>result 2>&1
done
. ../../testresult.sh
