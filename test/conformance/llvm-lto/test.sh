#!/bin/sh
. ../../testenv.sh
# Phase 12 step 2g: whole-program optimization, poc -lto.
#   1. a program built with -lto from source has the output of one built
#      without; at -opt 2 the call of Small.Twice, in another module, is
#      inlined and the procedure gone from the executable, which it is not
#      without -lto;
#   2. Small given as its .sym and .ll (-compile -lto, its source removed),
#      with -lto and without; with a .sym, an ordinary .o and a .ll, the .o
#      without -lto and the .ll with it; a bitcode .o alone refused;
#   3. a library built with -lto (its manifest says lto), linked without
#      -lto (the link has -flto all the same) and as a shared library;
#      poc-rtl built with -lto and used in place of poc's;
#   4. refused: a .ll compiled for -OC used under -O2, one whose target is
#      another, and one this clang cannot compile;
#   5. for 32-bit x86 NetBSD, -lto dropped with a warning, except on a host
#      whose clang targets 32-bit x86 NetBSD itself (yishana).
# The triple, keys and poc's library directory are masked.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(clang -dumpmachine)
pocLib=$(poc -print-library-path | tail -n 1)
mask() {
  sed -e "s|$pocLib|<poc lib>|g" -e "s|$triple|<triple>|g" -e 's/[0-9a-f]\{16\}/<key>/g'
}
# whether the executable $1 defines Small.Twice
twice() {
  if nm "$1" | grep -q 'Small\.Twice'; then echo "Small.Twice in $1"; else echo "no Small.Twice in $1"; fi
}
rm -rf work && mkdir work && cd work
: >../result
echo "== 1. from source" >>../result
mkdir one && cp ../src/Small.Mod ../src/main.mod one/
(cd one && poc -opt 2 -o plain -build main.mod 2>&1 | mask && ./plain >plain.out && cat plain.out) >>../result
(cd one && poc -opt 2 -lto -o lto -build main.mod 2>&1 | mask && ./lto >lto.out \
  && cmp plain.out lto.out && echo "same output") >>../result
(cd one && twice plain && twice lto) >>../result
echo "== 2. as .sym and .ll" >>../result
mkdir ir two && cp ../src/Small.Mod ir/ && cp ../src/main.mod two/
(cd ir && poc -lto -compile Small.Mod 2>&1 | mask && rm Small.Mod) >>../result
(cd two && poc -import-path ../ir -lto -verbose -o main -build main.mod 2>&1 | grep -c 'Small\.ir\.o' \
  && ./main) >>../result
echo "-- without -lto" >>../result
(cd two && rm -f *.o && poc -import-path ../ir -o main -build main.mod 2>&1 | mask && ./main) >>../result
echo "-- .sym, .o and .ll" >>../result
mkdir both && cp ../src/Small.Mod both/
(cd both && poc -compile Small.Mod 2>&1 | mask && rm Small.Mod) >>../result
(cd two && rm -f *.o && poc -import-path ../both -verbose -o main -build main.mod 2>&1 \
  | grep -c 'both/Small\.o' && ./main) >>../result
(cd two && rm -f *.o && poc -import-path ../both -lto -verbose -o main -build main.mod 2>&1 \
  | grep -c 'Small\.ir\.o' && ./main) >>../result
echo "-- a bitcode .o alone" >>../result
mkdir bitcode && cp ir/Small.sym ir/Small.o bitcode/
(cd two && rm -f *.o && poc -import-path ../bitcode -o main -build main.mod 2>&1 | mask) >>../result
echo "== 3. libraries" >>../result
mkdir three && cp ../src/Small.Mod three/ && cp ../src/main.mod two/
(cd three && poc -lto -output-dir lib -library small Small.Mod 2>&1 | mask) >>../result
grep -x lto three/lib/$triple/O2/small.library >>../result
(cd two && rm -f *.o && poc -library-path ../three/lib -verbose -o main -build main.mod 2>&1 \
  | grep '^clang' | grep -v '^clang -c' | grep -c ' -flto' && ./main) >>../result
(cd two && poc -library-path ../three/lib -shared-libraries -o mains -build main.mod 2>&1 | mask \
  && ./mains) >>../result
echo "-- poc-rtl built with -lto" >>../result
poc -lto -clear-library-path -output-dir rtl -library poc-rtl ../../../../rtl/llvm/*.Mod 2>&1 \
  | sed "s|$PWD/||" | mask >>../result
(cd one && poc -clear-library-path -library-path ../rtl -o main -build main.mod 2>&1 | mask && ./main) >>../result
(cd one && poc -clear-library-path -library-path ../rtl -lto -o main -build main.mod 2>&1 | mask \
  && ./main) >>../result
echo "== 4. refused" >>../result
mkdir oc && cp ../src/Small.Mod oc/
(cd oc && poc -OC -lto -compile Small.Mod >/dev/null 2>&1 && rm Small.Mod Small.o)
(cd two && poc -import-path ../oc -lto -o main -build main.mod 2>&1 | mask) >>../result
mkdir other && cp ir/Small.sym other/
sed 's/^@Small\.-target\.[^ ]* /@Small.-target.vax-dec-vms /' ir/Small.ll >other/Small.ll
(cd two && poc -import-path ../other -lto -o main -build main.mod 2>&1 | mask) >>../result
mkdir broken && cp ir/Small.sym broken/
{ cat ir/Small.ll; echo "this is not LLVM IR"; } >broken/Small.ll
(cd two && poc -import-path ../broken -lto -o main -build main.mod 2>&1 | grep '^poc:' | mask) >>../result
echo "== 5. for 32-bit x86 NetBSD" >>../result
# dropped with a warning unless this host's clang targets 32-bit x86
# NetBSD itself, where lld's executables run
mkdir five && printf 'MODULE Tiny;\n  PROCEDURE Two*(): INTEGER;\n  BEGIN RETURN 2\n  END Two;\nEND Tiny.\n' >five/Tiny.Mod
out=$(cd five && poc -lto -target i386-unknown-netbsd11.0 -compile Tiny.Mod 2>&1)
case $triple in
  i[3-6]86-*netbsd*) want= ;;
  *) want="poc: warning: -lto ignored for i386-unknown-netbsd11.0, which has no linker for LLVM bitcode" ;;
esac
if [ "$out" = "$want" ]; then echo "as this host should" >>../result; else echo "$out" >>../result; fi
cd ..
rm -rf work
. ../../testresult.sh
