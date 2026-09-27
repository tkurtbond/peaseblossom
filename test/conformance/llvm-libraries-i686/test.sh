#!/bin/sh
. ../../testenv.sh
# Phase 12 step 2h: libraries at the other word size. llvm-libraries' shapes
# (Lists, and Stacks, which imports it) built for 32-bit x86 (i686_triple),
# on a poc-rtl built for it too, under -O2 and -OC: each library's files, a
# program linked with them statically and with the shared libraries, both
# 32-bit and printing what llvm-libraries' main prints. Then what fails with
# a message: shapes on the path without the poc-rtl it needs, and a Lists.sym
# that does not match the shapes manifest (copied in from a Lists with one
# more procedure). Skips itself, still passing, where 32-bit x86 programs
# cannot run (i686_can_run). The triple, keys and OpenBSD's .so.0.0 are
# masked.
if ! i686_can_run
then
  echo "SKIPPED: no 32-bit x86 C runtime here (Fedora: dnf install glibc-devel.i686)"
  printf 'PASSED (skipped): %s\n\n' "$PWD"
  exit 0
fi
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(i686_triple)
mask() {
  sed -e "s|$triple|<i686>|g" -e 's/[0-9a-f]\{16\}/<key>/g' -e 's/\.so\.0\.0/.so/g'
}
poc() { command poc -clear-library-path -target $triple "$@"; }
# whether the executable $1 is 32-bit, and what it prints
run() {
  file "$1" | grep -q 'ELF 32-bit' && echo "$1: 32-bit" || echo "$1: NOT 32-BIT"
  "./$1"
}
rm -rf work && mkdir work && cd work
: >../result
for model in O2 OC; do
  echo "== -$model" >>../result
  poc -$model -output-dir lib -library poc-rtl ../../../../rtl/llvm/*.Mod 2>&1 | mask >>../result
  poc -$model -library-path lib -output-dir lib -library shapes \
    ../../llvm-libraries/src/Lists.Mod ../../llvm-libraries/src/Stacks.Mod 2>&1 | mask >>../result
  ls lib/$triple/$model | grep -e '^lib' -e '\.library$' | mask | LC_ALL=C sort >>../result
  poc -$model -library-path lib -o main$model -build ../../llvm-libraries/main.mod 2>&1 | mask >>../result
  run main$model >>../result
  poc -$model -library-path lib -shared-libraries -o mains$model -build ../../llvm-libraries/main.mod 2>&1 \
    | mask >>../result
  run mains$model >>../result
done
echo "== shapes without the poc-rtl it needs" >>../result
mkdir -p alone/$triple/O2 && cp lib/$triple/O2/Lists.* lib/$triple/O2/Stacks.* lib/$triple/O2/*shapes* alone/$triple/O2/
poc -library-path alone -o main -build ../../llvm-libraries/main.mod 2>&1 | mask >>../result
echo "== a Lists.sym the manifest does not have" >>../result
mkdir other && awk '/^BEGIN/ { print "  PROCEDURE Extra*;"; print "  END Extra;" } { print }' \
  ../../llvm-libraries/src/Lists.Mod >other/Lists.Mod
(cd other && poc -library-path ../lib -compile Lists.Mod >/dev/null 2>&1)
cp other/Lists.sym lib/$triple/O2/Lists.sym
poc -library-path lib -o main -build ../../llvm-libraries/main.mod 2>&1 | sed "s|$PWD/||" | mask >>../result
cd ..
rm -rf work
. ../../testresult.sh
