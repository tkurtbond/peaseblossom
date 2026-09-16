#!/bin/sh
# '.' this file from individual test.sh scripts, after producing "result".

if diff -b expected result
then printf 'PASSED: %s (%s)\n\n' "$PWD" "$BACKEND"
else printf 'FAILED: %s (%s)\n\n' "$PWD" "$BACKEND"; exit 1
fi
