#!/bin/sh
. ../../testenv.sh
# doc/developer/language-extensions.md, "External variables": variables a
# module's C part defines (part/Counters.c), declared ["C"] in
# part/Counters.Mod - an int under its own name, an array and a struct
# under linkage names - and used from UseCounters through the import:
# read, written, passed as VAR actuals, their addresses taken, and one
# declared again there under another name. Built from source; then
# Counters -compiled, its .sym (which keeps the attributes) printed, and
# UseCounters built against the pair, reading them from the .sym. The IR
# has each as an external global and defines none of them.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
rm -rf work && mkdir work && cd work || exit 1
: >../result
echo "== from source" >>../result
poc -import-path ../part -o fromsource -build ../usecounters.mod >>../result 2>&1
./fromsource >>../result
echo "== -compile, then the pair" >>../result
mkdir compiled pair && cd compiled
poc -compile ../../part/Counters.Mod >>../../result 2>&1
cat Counters.sym >>../../result
cd ../pair
poc -import-path ../compiled -o frompair -build ../../usecounters.mod >>../../result 2>&1
poc -import-path ../compiled -emit-llvm-ir ../../usecounters.mod >>../../result 2>&1
./frompair >>../../result
echo "== the IR's counter, counters_table and counters_pair" >>../../result
grep -hE '^@(counter|counters_table|counters_pair) ' ../compiled/Counters.ll UseCounters.ll \
  | LC_ALL=C sort -u >>../../result
cd ../..
rm -rf work
. ../../testresult.sh
