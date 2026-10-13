#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 1: an argument @file stands for the arguments in
# file, one a line, blanks at either end (and a CR) dropped and empty lines
# skipped, anywhere on the command line, a file naming another too, and
# @@text stands for @text, there and in a file (@at.mod is a module); on
# VMS, where DCL gives poc at most 255 characters of arguments, a long
# list goes in one (doc/developer/vax-macro32-backend.md, section 18.5).
# Each run's output and status; then what is refused.
rm -rf libs
rm -f resp-main
: >result
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
run @check.txt
run @options.txt
./resp-main >>result 2>&1
run -output-dir libs @library.txt
for f in RESP.library RespPart.sym; do
  ls libs/*/O2/$f >/dev/null 2>&1 && echo "the library has $f" >>result
done
run @lonely.txt RespPart.mod
run -check @@at.mod
run @quoted.txt
run @missing.txt
run @loop.txt
rm -rf libs
rm -f resp-main
. ../../testresult.sh
