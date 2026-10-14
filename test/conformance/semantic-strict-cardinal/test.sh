#!/bin/sh
. ../../testenv.sh
# -strict rejects the unsigned types, each where it is named (AGENTS.md,
# "Unsigned integer types"); without it the module is accepted.
: >result
poc -strict -check strict.mod >>result 2>&1
poc -check strict.mod >>result 2>&1
. ../../testresult.sh
