#!/bin/sh
. ../../testenv.sh
# Phase 12 step 2e: the four ways a program gets its modules.
#   1. its own modules and poc's runtime, linked from poc-rtl on poc's own
#      library path (no flags);
#   2. modules shared as source, through -import-path; not found without
#      it (the notes say where poc looked); as .sym and .o files, compiled
#      already (step 2f), but not as a .sym alone;
#   3. the user's own library, linked statically and as a shared library;
#      under -OC, or for a target, which it was not built for (a note says
#      what it was built for); with an edited copy of a module's source beside the program (a
#      warning: the library's is used);
#   4. libraries from others: blib needs alib (linked after it); without
#      alib on the path (notes name what blib needs); with clib, which has
#      Greet too, after alib (a warning: alib's hides it); alib rebuilt with
#      a new interface (blib refused, to be rebuilt);
#   5. modules compiled already, as .sym and .o (-compile, voc's -c): a
#      program linked with them, a library made of them (-library takes a
#      .sym or a .o for the pair) and a program linked with it; the
#      refusals - -compile given a .sym, another size model, another target, a .sym
#      the .o was not compiled from, an import whose interface has changed;
#   and installing: alib and blib into one directory, again (replaced),
#   over a copy another version of poc wrote that has a module alib no
#   longer has (replaced, that module's files removed),
#   from that directory itself and clib, which has Greet too (refused), a
#   library that is not there; and a program linked with the installed
#   shared libraries still running after it and they are copied elsewhere
#   together and the originals moved away (its run-time search path is
#   relative to it).
# The import path is empty; the library path is poc's own lib/poc, which
# has poc-rtl, and what each command adds. The triple, keys and that
# directory are masked.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(clang -dumpmachine)
pocLib=$(poc -print-library-path | tail -n 1)
mask() {
  sed -e "s|$pocLib|<poc lib>|g" -e "s|$triple|<triple>|g" -e 's/[0-9a-f]\{16\}/<key>/g' \
      -e 's/^poc [0-9][0-9.]*$/poc <version>/'
}
rm -rf work && mkdir work && cd work
: >../result
echo "== 1. own modules and the runtime" >>../result
mkdir one && cp ../src/Greet.Mod ../src/main.mod one/
(cd one && poc -o main -build main.mod 2>&1 | mask && ./main) >>../result
echo "== 2. modules shared as source" >>../result
mkdir two && cp ../src/main.mod two/
(cd two && poc -import-path ../one -o main -build main.mod 2>&1 | mask && ./main) >>../result
echo "-- without -import-path" >>../result
(cd two && rm -f *.sym *.ll *.o && poc -o main -build main.mod 2>&1 | mask) >>../result
echo "-- as Greet.sym and Greet.o, compiled already" >>../result
mkdir compiled && cp one/Greet.sym one/Greet.o compiled/
(cd two && rm -f *.sym *.ll *.o && poc -import-path ../compiled -o main -build main.mod 2>&1 | mask \
  && ./main) >>../result
echo "-- Greet.sym alone" >>../result
mkdir symonly && cp one/Greet.sym symonly/
(cd two && rm -f *.sym *.ll *.o && poc -import-path ../symonly -o main -build main.mod 2>&1 | mask) >>../result
echo "== 3. own library" >>../result
mkdir three && cp ../src/Greet.Mod ../src/Twice.Mod three/
(cd three && poc -output-dir lib -library mine Greet.Mod Twice.Mod 2>&1 | mask) >>../result
mkdir app && cp ../src/app.mod app/
(cd app && poc -library-path ../three/lib -o app -build app.mod 2>&1 | mask && ./app) >>../result
echo "-- shared" >>../result
(cd app && poc -library-path ../three/lib -shared-libraries -o apps -build app.mod 2>&1 | mask && ./apps) >>../result
echo "-- -OC" >>../result
(cd app && poc -OC -library-path ../three/lib -o app -build app.mod 2>&1 | mask) >>../result
echo "-- built for another target only" >>../result
mkdir -p elsewhere/sparc64-unknown-netbsd && cp -r three/lib/$triple/O2 elsewhere/sparc64-unknown-netbsd/
(cd app && poc -library-path ../elsewhere -o app -build app.mod 2>&1 | mask) >>../result
echo "-- an edited Greet.Mod beside the program" >>../result
sed 's/"hi "/"hello "/' ../src/Greet.Mod >app/Greet.Mod
(cd app && poc -library-path ../three/lib -o app -build app.mod 2>&1 | mask && ./app) >>../result
echo "== 4. libraries from others" >>../result
mkdir a b c four && cp ../src/Greet.Mod a/ && cp ../src/Greet.Mod c/ && cp ../others/Loud.Mod b/
cp ../others/app.mod four/
(cd a && poc -output-dir ../liba -library alib Greet.Mod 2>&1 | mask) >>../result
(cd b && poc -library-path ../liba -output-dir ../libb -library blib Loud.Mod 2>&1 | mask) >>../result
(cd c && poc -output-dir ../libc -library clib Greet.Mod 2>&1 | mask) >>../result
grep needs libb/$triple/O2/blib.library >>../result
(cd four && poc -library-path ../liba -library-path ../libb -o app -build app.mod 2>&1 | mask && ./app) >>../result
echo "-- without alib" >>../result
(cd four && poc -library-path ../libb -o app -build app.mod 2>&1 | mask) >>../result
echo "-- clib after alib" >>../result
(cd four && poc -library-path ../liba -library-path ../libb -library-path ../libc -o app -build app.mod 2>&1 \
  | mask && ./app) >>../result
echo "== installing" >>../result
poc -library-path liba -output-dir inst -install-library alib 2>&1 | mask >>../result
poc -library-path libb -library-path liba -output-dir inst -install-library blib 2>&1 | mask >>../result
ls inst/$triple/O2 | sed 's/\.so\.0\.0$/.so/' | LC_ALL=C sort >>../result
echo "-- again" >>../result
poc -library-path liba -output-dir inst -install-library alib 2>&1 | mask >>../result
echo "-- over a copy another poc wrote, with a module it no longer has" >>../result
sed 's/^poc .*/poc 0.0.1/' inst/$triple/O2/alib.library >inst/alib.old
echo "module Gone 0000000000000000" >>inst/alib.old
mv inst/alib.old inst/$triple/O2/alib.library
echo alib >inst/$triple/O2/Gone.owner && : >inst/$triple/O2/Gone.sym
poc -library-path liba -output-dir inst -install-library alib 2>&1 | mask >>../result
ls inst/$triple/O2 | grep Gone >>../result || echo "Gone's files removed" >>../result
grep '^poc ' inst/$triple/O2/alib.library | sed 's/[0-9][0-9.]*$/<version>/' >>../result
echo "-- from where it is" >>../result
poc -library-path inst -output-dir inst -install-library alib 2>&1 | mask >>../result
echo "-- clib, which has Greet too" >>../result
poc -library-path libc -output-dir inst -install-library clib 2>&1 | mask >>../result
echo "-- no such library" >>../result
poc -output-dir inst -install-library nosuch 2>&1 | mask >>../result
echo "-- a program, moved with the libraries" >>../result
mkdir four/bin
(cd four && poc -library-path ../inst -shared-libraries -o bin/app -build app.mod 2>&1 | mask && ./bin/app) \
  >>../result
mkdir moved && cp -r inst moved/ && mkdir moved/four && cp -r four/bin moved/four/
mv inst inst.away && mv liba liba.away && mv libb libb.away
moved/four/bin/app >>../result 2>&1
mv inst.away inst && mv liba.away liba && mv libb.away libb
echo "-- alib with a new interface" >>../result
awk '/^  PROCEDURE Hi\*/ { print "  PROCEDURE Bye*;"; print "  END Bye;"; print "" } { print }' \
  ../src/Greet.Mod >a/Greet.Mod
(cd a && poc -output-dir ../liba -library alib Greet.Mod 2>&1 | mask) >>../result
(cd four && poc -library-path ../liba -library-path ../libb -o app -build app.mod 2>&1 | mask) >>../result
echo "== 5. modules compiled already" >>../result
# Greet and Twice compiled to .sym and .o (-compile), their source then
# removed: a program linked with them, a library of them, and a program
# linked with that
mkdir pairs && cp ../src/Greet.Mod ../src/Twice.Mod pairs/
(cd pairs && poc -compile Greet.Mod Twice.Mod 2>&1 | mask && rm Greet.Mod Twice.Mod *.ll) >>../result
ls pairs >>../result
(cd app && rm -f Greet.Mod *.sym *.ll *.o && poc -import-path ../pairs -o app -build app.mod 2>&1 | mask \
  && ./app) >>../result
echo "-- a library of them" >>../result
poc -output-dir pairlib -library fromobjects pairs/Greet.o pairs/Twice.sym 2>&1 | mask >>../result
grep -v '^triple' pairlib/$triple/O2/fromobjects.library | mask >>../result
(cd app && rm -f Greet.Mod *.sym *.ll *.o && poc -library-path ../pairlib -o app -build app.mod 2>&1 | mask \
  && ./app) >>../result
echo "-- -compile given a .sym" >>../result
poc -compile pairs/Greet.sym 2>&1 | mask >>../result
echo "-- under -OC" >>../result
(cd app && poc -OC -import-path ../pairs -o app -build app.mod 2>&1 | mask) >>../result
echo "-- for another target" >>../result
(cd app && poc -clear-library-path -import-path ../../../../../rtl/llvm -import-path ../pairs \
   -target sparc64-unknown-netbsd -o app -build app.mod 2>&1 | mask) >>../result
echo "-- a .sym that is not the .o's" >>../result
mkdir other && cp pairs/* other/ && sed 's/Hi\*(n: INTEGER)/Hi*(n: LONGINT)/' pairs/Greet.sym >other/Greet.sym
(cd app && poc -import-path ../other -o app -build app.mod 2>&1 | mask) >>../result
echo "-- Twice.o compiled against another Greet" >>../result
mkdir newer && cp pairs/Twice.sym pairs/Twice.o newer/
awk '/^  PROCEDURE Hi\*/ { print "  PROCEDURE Bye*;"; print "  END Bye;"; print "" } { print }' \
  ../src/Greet.Mod >newer/Greet.Mod
(cd app && poc -import-path ../newer -o app -build app.mod 2>&1 | mask) >>../result
cd ..
rm -rf work
. ../../testresult.sh
