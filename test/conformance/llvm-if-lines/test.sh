#!/bin/sh
. ../../testenv.sh
# An IF's and its ELSIFs' positions, as -g's debug locations show them on
# the conditional branches: the parser once gave the IF the position of
# its last ELSIF, and the code generator gave each ELSIF's condition the
# position of the body before it.
poc -g -opt 0 -target x86_64-unknown-linux-gnu -emit-llvm-ir IfLines.mod >result 2>&1
sed -n 's/^ *\(br i1\) .*\(line: [0-9]*, column: [0-9]*\).*/\1 \2/p' IfLines.ll >>result
. ../../testresult.sh
