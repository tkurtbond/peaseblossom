#!/bin/sh
. ../../testenv.sh
# doc/developer/static-only-libraries.md, step 1: -no-shared-library goes
# with -library, before the command or after the file, and the manifest
# says so in a line of its own, which a later poc can read: a program
# links the library. Without the option there is no such line. Any other
# command refuses the option; for vax-dec-vms, fixture
# poc-vax-target-llvm-options.
unset POC_IMPORT_PATH
triple=$(clang -dumpmachine)
manifest() { grep -c '^no-shared$' "$1/$triple/O2/greet.library"; }
rm -rf work && mkdir work && cd work || exit 1
: >../result
echo "== before the command" >>../result
poc -output-dir before -no-shared-library -library greet ../Greet.Mod >>../result 2>&1
echo "exit=$?" >>../result
manifest before >>../result
echo "== after the file" >>../result
poc -output-dir after -library greet ../Greet.Mod -no-shared-library >>../result 2>&1
echo "exit=$?" >>../result
manifest after >>../result
echo "== without it" >>../result
poc -output-dir without -library greet ../Greet.Mod >>../result 2>&1
echo "exit=$?" >>../result
manifest without >>../result
echo "== a program reads the manifest" >>../result
poc -library-path before -o main -build ../main.mod >>../result 2>&1
echo "exit=$?" >>../result
./main >>../result 2>&1
echo "== other commands" >>../result
for command in "-build ../main.mod" "-compile ../main.mod" "-check ../main.mod" "../main.mod"; do
  echo "-- $command" >>../result
  poc -library-path before -no-shared-library $command >>../result 2>&1
  echo "exit=$?" >>../result
done
cd .. || exit 1
rm -rf work
. ../../testresult.sh
