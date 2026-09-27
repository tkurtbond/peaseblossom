#!/bin/sh
. ../../testenv.sh
# Phase 12 step 2b: module keys. Each module's object defines
# <Module>.-key.<hash of its .sym>, and an importer's object refers to the
# keys of the modules it was compiled against. The client is compiled once,
# against libv1; lib is then recompiled alone and the old client.o linked
# with it: a new body keeps lib's key and links; a new interface changes it,
# and the link fails, naming the key the client needs.
POC_IMPORT_PATH=$PWD/../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
rm -rf work && mkdir work
cp client.mod libonly.mod work/
cd work
cp ../libv1.mod lib.mod
: >../result
echo "== client and lib v1" >>../result
poc -o "$exe" -build client.mod >/dev/null 2>&1
"./$exe" >>../result
grep -h -e '-key\.' client.ll lib.ll | sed -e 's/\.-key\.[0-9a-f]*/.-key.<hash>/g' >>../result
lib1=$(sed -n 's/^@lib\.-key\.\([0-9a-f]*\) = constant.*/\1/p' lib.ll)
# lib compiled without client, as a library will be (libonly.mod imports
# only lib, so lib.ll has no main)
relink() {
  cp "$1" lib.mod
  poc -emit-llvm-ir libonly.mod >/dev/null
  clang -c lib.ll -o lib.o
  lib2=$(sed -n 's/^@lib\.-key\.\([0-9a-f]*\) = constant.*/\1/p' lib.ll)
  if [ "$lib1" = "$lib2" ]; then echo "lib's key: unchanged" >>../result
  else echo "lib's key: changed" >>../result
  fi
  objs=$(sed -n "s/^clang --target=[^ ]* -O[^ ]* \\(.*\\) -o '$exe'.*/\\1/p" link.cmd)
  if eval clang $objs -o relinked -lm 2>link.err; then
    echo "link: ok" >>../result
    ./relinked >>../result
  else
    echo "link: failed" >>../result
    # GNU ld and lld word it differently; both name the symbol
    if grep -q "undefined.*lib\.-key\.$lib1" link.err
    then echo "the linker names lib.-key.<the hash client.o was compiled against> undefined" >>../result
    else cat link.err >>../result
    fi
  fi
}
poc -verbose -o "$exe" -build client.mod 2>&1 >/dev/null | tail -1 >link.cmd
echo "== lib with a new body" >>../result
relink ../libbody.mod
echo "== lib with a new interface" >>../result
relink ../libv2.mod
cd ..
rm -rf work
. ../../testresult.sh
