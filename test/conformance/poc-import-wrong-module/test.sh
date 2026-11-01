#!/bin/sh
. ../../testenv.sh
# "Ongoing bug fixing" 12 and 13 in PLAN.md: a module is named by its source,
# and an import finds a file by the name imported. So a file that declares
# another module cannot be imported: poc says so, naming the file and both
# modules, and writes no .sym for the module the file does declare. A name
# that differs only in case differs. The file named on the command line can
# have any name, its outputs being named after its module.
unset POC_IMPORT_PATH
rm -rf work && mkdir work && cd work || exit 1
cp ../*.Mod ../*.mod . || exit 1
: >../result
run() {
  echo "== poc $*" >>../result
  poc "$@" >>../result 2>&1
  echo "exit=$?" >>../result
  ls | grep -E '\.sym$' | sed 's/^/written: /' | LC_ALL=C sort >>../result
  rm -f *.sym
}
run -build direct.mod
run -compile direct.mod
run -emit-llvm-ir direct.mod
run -target vax-dec-vms -build direct.mod
run -build deep.mod
run -build incase.mod
run -output-dir . -library named Named.Mod
echo "== a file of another name on the command line" >>../result
poc -build program.mod >>../result 2>&1
echo "exit=$?" >>../result
ls | grep -E '^Hello(\.sym)?$' | LC_ALL=C sort >>../result
./Hello >>../result 2>&1
cd .. || exit 1
rm -rf work
. ../../testresult.sh
