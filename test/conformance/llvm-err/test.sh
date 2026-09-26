#!/bin/sh
. ../../testenv.sh
# rtl/llvm/Err.Mod (Phase 11 A26): errtest writes each item to Out and then
# to Err. result has the program's two streams on one file, so it shows that
# they come out in the order of the calls; the program is also run with the
# streams apart, and the two must carry the same text, bar the last line
# (" at the end" on standard error, "no newline" on standard output).
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
poc -o "$exe" -build errtest.mod >result 2>&1
"./$exe" >>result 2>&1
echo >>result
"./$exe" >stdout.txt 2>stderr.txt
sed '$d' stdout.txt >stdout.head
sed '$d' stderr.txt >stderr.head
cmp -s stdout.head stderr.head || echo "standard output and standard error differ" >>result
[ "$(tail -n 1 stdout.txt)" = "no newline" ] || echo "standard output's last line is wrong" >>result
[ "$(tail -n 1 stderr.txt)" = " at the end" ] || echo "standard error's last line is wrong" >>result
rm -f stdout.txt stderr.txt stdout.head stderr.head
. ../../testresult.sh
