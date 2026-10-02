#!/bin/sh
. ../../testenv.sh
# Phase 12 step 5a: a module's part in C, part/Twice.c beside part/Twice.Mod,
# compiled by poc whenever it compiles the module and linked wherever the
# module's object goes: a program built from source; -compile, which leaves
# Twice.c.o beside Twice.o, and a program that takes Twice from that pair;
# and a library, static and shared. The C object's name is printed as poc
# makes it (the host's triple masked); Out comes from poc's own poc-rtl.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(clang -dumpmachine)
mask() { sed -e "s|$triple|<triple>|g" -e 's/[0-9a-f]\{16\}/<key>/g' -e 's/libtwice\.so\.0\.0/libtwice.so/'; }
rm -rf work && mkdir work && cd work
: >../result
echo "== from source" >>../result
poc -import-path ../part -o fromsource -build ../usetwice.mod 2>&1 | mask >>../result
ls | grep '^Twice\.' | LC_ALL=C sort >>../result
./fromsource >>../result
echo "== -compile, then the pair" >>../result
mkdir compiled pair && cd compiled
poc -compile ../../part/Twice.Mod 2>&1 | mask >>../../result
ls | LC_ALL=C sort >>../../result
cd ../pair
poc -import-path ../compiled -o frompair -build ../../usetwice.mod 2>&1 | mask >>../../result
./frompair >>../../result
cd ..
echo "== a library" >>../result
poc -output-dir lib -library twice ../part/Twice.Mod 2>&1 | mask >>../result
ar t lib/$triple/O2/libtwice.a | LC_ALL=C sort >>../result
poc -library-path lib -o fromlibrary -build ../usetwice.mod 2>&1 | mask >>../result
./fromlibrary >>../result
poc -library-path lib -shared-libraries -o fromshared -build ../usetwice.mod 2>&1 | mask >>../result
./fromshared >>../result
cd ..
rm -rf work
. ../../testresult.sh
