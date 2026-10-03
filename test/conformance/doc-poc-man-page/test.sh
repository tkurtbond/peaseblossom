#!/bin/sh
. ../../testenv.sh
# Phase 13 step 9: poc(1), doc/poc.1, must lint clean with mandoc at the
# warning level (STYLE notes, such as the missing Mdocdate and RCS id, are
# expected and not shown). Skips itself, still passing, where there is no
# mandoc; every gating host has one.
if ! command -v mandoc >/dev/null 2>&1
then
  echo "SKIPPED: no mandoc here"
  printf 'PASSED (skipped): %s\n\n' "$PWD"
  exit 0
fi
mandoc -T lint -W warning ../../../doc/poc.1 >result 2>&1
echo "exit $?" >>result
. ../../testresult.sh
exit 0
