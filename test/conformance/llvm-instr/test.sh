#!/bin/sh
. ../../testenv.sh
# InStr (PLAN.md, "Ongoing library enhancements" 2): the same tokens as In,
# reading input.txt from standard input and from a string; then InStr's own
# positions. Both size models give the same output.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build instr.mod >result 2>&1
"./$exe" in <input.txt >in.out
"./$exe" instr <input.txt >>result
sed '/^-- InStr only/,$d' result | grep -v '^pos ' >instr.out
cmp -s in.out instr.out || { echo "In and InStr differ:" >>result; diff in.out instr.out >>result; }
rm -f in.out instr.out
poc -OC -o "$exe" -build instr.mod >result.oc 2>&1
"./$exe" instr <input.txt >>result.oc
cmp -s result result.oc || { echo "-OC output differs:" >>result; cat result.oc >>result; }
rm -f result.oc
. ../../testresult.sh
