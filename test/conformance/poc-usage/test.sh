#!/bin/sh
. ../../testenv.sh
# Phase 12 step 1, and 2026-10-05: poc with no arguments prints -help's
# list of every command and option on stderr and exits with status 1; a
# command line poc cannot use gets one line saying what is wrong, and a
# pointer to -help, not the whole list in which the mistake would be lost:
# an unknown option, before a file and alone; a command without its file;
# and flags with no command after them (until Phase 12 step 1 poc exited
# with status 0, having done nothing).
poc >result 2>&1
printf 'exit=%d\n' "$?" >>result
echo "== the same as -help" >>result
poc -help >help 2>&1
poc >no-args 2>&1
if cmp -s help no-args; then echo "the same text" >>result; else echo "not the same" >>result; fi
rm -f help no-args
for args in "-frobnicate ok.mod" "-frobnicate" "-check" "-O2 -static"; do
  echo "== poc $args" >>result
  poc $args >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
. ../../testresult.sh
