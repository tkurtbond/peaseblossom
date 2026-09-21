#!/bin/sh
. ../../testenv.sh
# A construct the LLVM backend cannot lower (an external procedure with the
# VMS calling convention, which only the VAX backend will have) used to compile
# to a plain C call, and the build failed at link time, or worse succeeded
# calling the wrong thing. Now it is an error naming its line, and neither IR
# nor an executable is written. (This fixture began with a nested procedure and
# then a ninth open dimension as its example; nested procedures are lowered now
# and the ninth dimension is the front end's error, see
# semantic-reject-open-array-dimensions.)
exe=$(basename "$PWD")
poc -o "$exe" -build vms.mod >result
[ -e vms.ll ] && echo "IR WAS WRITTEN" >>result
[ -e "$exe" ] && echo "EXECUTABLE WAS WRITTEN" >>result
poc -emit-llvm-ir vms.mod >>result
[ -e vms.ll ] && echo "IR WAS WRITTEN" >>result
echo "done" >>result
# a failed run must not leave its half-written IR behind
ls -A | grep '^[.]tmp' >/dev/null && echo "LEFTOVER TEMP FILE" >>result
. ../../testresult.sh
