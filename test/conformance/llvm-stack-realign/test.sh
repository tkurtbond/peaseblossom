#!/bin/sh
. ../../testenv.sh
# The module flag and main's attribute for 32-bit x86 BSD triples, and their
# absence for Linux, a 64-bit BSD and a 32-bit ARM BSD. Every .ll is also
# handed to clang for its own triple; a clang built without that target (the
# OpenBSD one has only x86) says so and is not held against the IR, so the
# result is the same on every host.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for triple in i686-unknown-linux-gnu i386-unknown-netbsd11.0 i386-unknown-openbsd7.9 \
              i386-unknown-freebsd15.0 x86_64-unknown-netbsd11.0 armv7-unknown-freebsd15.0; do
  for source in realign plain; do
    echo "== $triple $source" >>result
    poc -target $triple -emit-llvm-ir $source.mod >/dev/null
    grep -E '^(!|define i32 @main)' $source.ll >>result
    if clang -target $triple -c $source.ll -o /dev/null 2>clang.err
    then :
    elif grep 'No available targets' clang.err >/dev/null
    then :
    else echo "clang REJECTED" >>result; cat clang.err >>result
    fi
    rm -f clang.err
  done
done
. ../../testresult.sh
