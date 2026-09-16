#!/bin/sh
# '.' this file from individual test.sh scripts, after producing "result".

if diff -b expected result
then printf 'PASSED: %s\n\n' "$PWD"
else printf 'FAILED: %s\n\n' "$PWD"; exit 1
fi
