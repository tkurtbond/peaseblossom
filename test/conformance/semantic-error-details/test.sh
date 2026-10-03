#!/bin/sh
. ../../testenv.sh
# Phase 13 step 2: a compile error names what it is about, "message:
# details" - an identifier, qualified when it was; the types of an
# assignment, argument or operands; the names of a mismatched END.
poc -emit-interface lib.mod >/dev/null
{ poc -check details.mod; poc -check ends.mod; } >result 2>&1
rm -f lib.sym
. ../../testresult.sh
