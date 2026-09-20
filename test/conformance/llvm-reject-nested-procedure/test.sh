#!/bin/sh
. ../../testenv.sh
# A procedure declared inside another needs the enclosing one's locals, which
# this backend cannot give it yet. It used to compile to "; unsupported"
# comments where the calls were, and the build succeeded with the program
# quietly doing less than its source says (here: printing WRONG). Now every
# such declaration and call is an error naming its line, and neither IR nor
# an executable is written.
exe=$(basename "$PWD")
poc -o "$exe" -build nested.mod >result
[ -e nested.ll ] && echo "IR WAS WRITTEN" >>result
[ -e "$exe" ] && echo "EXECUTABLE WAS WRITTEN" >>result
poc -emit-llvm-ir nested.mod >>result
[ -e nested.ll ] && echo "IR WAS WRITTEN" >>result
echo "done" >>result
. ../../testresult.sh
