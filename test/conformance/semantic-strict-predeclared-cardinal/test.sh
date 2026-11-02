#!/bin/sh
. ../../testenv.sh
# -strict rejects the predeclared unsigned types and VAL, each where named
# (doc/developer/language-extensions.md, "Predeclared unsigned types");
# without it the module is accepted.
: >result
poc -strict -check strict.mod >>result 2>&1
poc -check strict.mod >>result 2>&1
. ../../testresult.sh
