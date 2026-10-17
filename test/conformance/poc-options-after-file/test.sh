#!/bin/sh
. ../../testenv.sh
# The user, 2026-10-17: an option after the file, or among -compile's or
# -library's files, applies as one before it does (until then poc ignored
# an option after the file, and read one among the files as a file). For
# each kind of command, an option after its file, and what it changes.
rm -rf ir objs after-main
: >result
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
run After.mod -o after-main
./after-main >>result 2>&1
run -check Strict.mod -strict
run -emit-llvm-ir After.mod -output-dir ir
ls ir >>result
run -compile After.mod -O2 Second.mod -output-dir objs
ls objs >>result
run -emit-macro32 Trap.mod -target vax-dec-vms -trap-location
grep -c 'L_FILE_NAME:' Trap.mar >>result
run -print-import-path -clear-import-path -import-path nowhere
run After.mod -frobnicate
rm -rf ir objs after-main Trap.mar
. ../../testresult.sh
