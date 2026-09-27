#!/bin/sh
. ../../testenv.sh
# Phase 12 step 1: poc with no command prints its usage on stderr and exits
# with status 1; the text lists every command and flag. Flags with no command
# after them do the same (until Phase 12 step 1 poc exited with status 0,
# having done nothing).
poc >result 2>&1
printf 'exit=%d\n' "$?" >>result
echo "== flags and no command" >>result
poc -O2 -static >flags-only 2>&1
status=$?
poc >no-args 2>&1
if cmp -s flags-only no-args; then echo "the same usage text" >>result; else cat flags-only >>result; fi
printf 'exit=%d\n' "$status" >>result
rm -f flags-only no-args
. ../../testresult.sh
