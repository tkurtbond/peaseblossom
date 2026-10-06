#!/bin/sh
. ../../testenv.sh
# PLAN.md's Ongoing implementation enhancements, items 1 and 2: a module's
# part in C++, part/Greet.cpp, compiled by clang++, and whatever links it
# linked by clang++, for the C++ runtime; and a library's manifest
# recording the -link arguments it was built with (here for libnative.a,
# which Greet.cpp uses), which every program that links the library -
# directly, or through a library that needs it - then gets without naming
# them. A module with both a C and a C++ part is refused.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(clang -dumpmachine)
rm -rf work && mkdir work && cd work
here=$PWD
mask() { sed -e "s|$triple|<triple>|g" -e "s|$here|<work>|g" -e 's/[0-9a-f]\{16\}/<key>/g'; }
: >../result
mkdir native
clang -c -fPIC ../native/native.c -o native/native.o && ar rcs native/libnative.a native/native.o
echo "== from source" >>../result
mkdir source && cd source
poc -import-path ../../part -link -L"$here/native" -link -lnative -o fromsource -build ../../usegreet.mod 2>&1 | mask >>../../result
ls | grep '^Greet\.' | LC_ALL=C sort >>../../result
./fromsource >>../../result
cd ..
echo "== -compile, then the pair" >>../result
mkdir compiled pair && cd compiled
poc -compile ../../part/Greet.Mod 2>&1 | mask >>../../result
ls | LC_ALL=C sort >>../../result
cd ../pair
poc -import-path ../compiled -link -L"$here/native" -link -lnative -o frompair -build ../../usegreet.mod 2>&1 | mask >>../../result
./frompair >>../../result
cd ..
echo "== a library, and its manifest's c++ and link lines" >>../result
poc -output-dir lib -link -L"$here/native" -link -lnative -library greet ../part/Greet.Mod 2>&1 | mask >>../result
grep -e '^c++' -e '^link' lib/$triple/O2/greet.library | mask >>../result
ar t lib/$triple/O2/libgreet.a | LC_ALL=C sort >>../result
poc -library-path lib -o fromlibrary -build ../usegreet.mod 2>&1 | mask >>../result
./fromlibrary >>../result
poc -library-path lib -shared-libraries -o fromshared -build ../usegreet.mod 2>&1 | mask >>../result
./fromshared >>../result
echo "== a library that needs it" >>../result
poc -library-path lib -output-dir lib2 -library greeter ../part/Greeter.Mod 2>&1 | mask >>../result
grep -e '^needs' -e '^c++' -e '^link' lib2/$triple/O2/greeter.library | mask >>../result
poc -library-path lib2 -library-path lib -o fromgreeter -build ../usegreeter.mod 2>&1 | mask >>../result
./fromgreeter >>../result
poc -library-path lib2 -library-path lib -shared-libraries -o fromgreetershared -build ../usegreeter.mod 2>&1 | mask >>../result
./fromgreetershared >>../result
echo "== a C part and a C++ part" >>../result
poc -import-path ../both -o both -build ../useboth.mod 2>&1 | mask | sed 's|[^ ]*/both/|<both>/|g' >>../result
cd ..
rm -rf work
. ../../testresult.sh
