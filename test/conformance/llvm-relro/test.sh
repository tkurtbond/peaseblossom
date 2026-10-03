#!/bin/sh
. ../../testenv.sh
# Phase 13 step 8: an executable poc links and a shared library it builds
# each have a GNU_RELRO segment, on every system: Linux's and the other
# BSDs' linkers give one unasked, on NetBSD poc passes -Wl,-z,relro (plain
# clang and gcc there do not; pkgsrc's checks found it). The program is
# linked with the shared library, so it runs only if that works too.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
rm -rf lib
: >result
poc -output-dir lib -library greeting Greeting.mod >>result 2>&1
so=$(ls lib/*/*/libgreeting.so* | head -1)
printf 'library: %s\n' "$(readelf -lW "$so" | grep -c GNU_RELRO)" >>result
poc -library-path lib -shared-libraries -o "$exe" -build relro.mod >>result 2>&1
printf 'program: %s\n' "$(readelf -lW "$exe" | grep -c GNU_RELRO)" >>result
"./$exe" >>result 2>&1
rm -rf lib
. ../../testresult.sh
