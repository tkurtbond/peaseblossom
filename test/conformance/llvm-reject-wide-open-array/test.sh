#!/bin/sh
. ../../testenv.sh
# A construct the backend cannot lower yet (an open array parameter of more
# than 8 dimensions, the most a dope vector holds) used to compile to
# "; unsupported" comments and the build succeeded with the program quietly
# doing less than its source says. Now it is an error naming its line, and
# neither IR nor an executable is written. (This fixture was about nested
# procedures until Phase 11 step 8 lowered them all; the crash it once hid,
# a run-time index error in poc itself on a ninth dimension, is fixed too.)
exe=$(basename "$PWD")
poc -o "$exe" -build wide.mod >result
[ -e wide.ll ] && echo "IR WAS WRITTEN" >>result
[ -e "$exe" ] && echo "EXECUTABLE WAS WRITTEN" >>result
poc -emit-llvm-ir wide.mod >>result
[ -e wide.ll ] && echo "IR WAS WRITTEN" >>result
echo "done" >>result
# a failed run must not leave its half-written IR behind
ls -A | grep '^[.]tmp' >/dev/null && echo "LEFTOVER TEMP FILE" >>result
. ../../testresult.sh
