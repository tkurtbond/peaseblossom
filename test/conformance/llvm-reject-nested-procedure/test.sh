#!/bin/sh
. ../../testenv.sh
# A procedure declared inside another that uses variables of the enclosing one
# needs them handed over, which this backend cannot do yet (Phase 11 step 8,
# step 3). It used to compile to "; unsupported" comments where the calls were,
# and the build succeeded with the program quietly doing less than its source
# says (here: printing WRONG). Now the declaration and every call of it is an
# error naming its line, and neither IR nor an executable is written. Inner,
# which uses only a global, is lowered (llvm-nested-basic) and not reported.
exe=$(basename "$PWD")
poc -o "$exe" -build nested.mod >result
[ -e nested.ll ] && echo "IR WAS WRITTEN" >>result
[ -e "$exe" ] && echo "EXECUTABLE WAS WRITTEN" >>result
poc -emit-llvm-ir nested.mod >>result
[ -e nested.ll ] && echo "IR WAS WRITTEN" >>result
echo "done" >>result
# a failed run must not leave its half-written IR behind
ls -A | grep '^[.]tmp' >/dev/null && echo "LEFTOVER TEMP FILE" >>result
. ../../testresult.sh
