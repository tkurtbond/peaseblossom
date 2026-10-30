#!/bin/sh
. ../../testenv.sh
# Object files named on the command line (PLAN.md, "Ongoing implementation
# enhancements", item 9; llvm-toolchain.md, "Object files on the command
# line"). twice.o, compiled here from twice-source.txt, is linked into a
# program by -build and by a bare file, and under -lto; put into the library
# quad beside Quad's object, in its archive (ar t) and its shared library,
# and recorded in its manifest; and a program using quad gets it from either.
# Then what poc refuses: an object for -check and -compile, a missing one, a
# module's own .o for -build, and for -library an object named as a member
# already is (a module's object or another object) or with a space in its
# name. The host's triple and the keys are masked.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
triple=$(clang -dumpmachine)
mask() {
  sed -e "s|$triple|<triple>|g" -e 's/[0-9a-f]\{16\}/<key>/g' \
      -e 's/^poc [0-9][0-9.]*$/poc <version>/'
}
rm -rf work && mkdir work && cd work || exit 1
: >../result
clang -x c -c -fPIC ../twice-source.txt -o twice.o
echo "== -build" >>../result
poc -build ../Use.Mod twice.o 2>&1 | mask >>../result
./Use >>../result
echo "== a bare file" >>../result
poc -o use2 ../Use.Mod twice.o 2>&1 | mask >>../result
./use2 >>../result
echo "== -lto" >>../result
poc -lto -o use3 ../Use.Mod twice.o 2>&1 | mask >>../result
./use3 >>../result
echo "== -library" >>../result
poc -output-dir lib -library quad ../Quad.Mod twice.o 2>&1 | mask >>../result
mask <lib/$triple/O2/quad.library >>../result
ar t lib/$triple/O2/libquad.a | LC_ALL=C sort >>../result
echo "== a program using it" >>../result
poc -library-path lib -build ../Main.Mod 2>&1 | mask >>../result
./Main >>../result
poc -library-path lib -shared-libraries -o mains -build ../Main.Mod 2>&1 | mask >>../result
./mains >>../result
echo "== -check and -compile" >>../result
poc -check ../Use.Mod twice.o >>../result 2>&1
echo "exit=$?" >>../result
poc -compile ../Use.Mod twice.o >>../result 2>&1
echo "exit=$?" >>../result
echo "== a missing object" >>../result
poc -build ../Use.Mod missing.o >>../result 2>&1
echo "exit=$?" >>../result
echo "== a module's object" >>../result
poc -compile ../Quad.Mod 2>&1 | mask >>../result
poc -build ../Main.Mod Quad.o >>../result 2>&1
echo "exit=$?" >>../result
echo "== a member's name" >>../result
mkdir other && cp twice.o other/Quad.o && cp twice.o other/twice.o && cp twice.o "other/a b.o"
poc -output-dir lib2 -library quad2 ../Quad.Mod other/Quad.o >>../result 2>&1
echo "exit=$?" >>../result
poc -output-dir lib2 -library quad2 ../Quad.Mod twice.o other/twice.o >>../result 2>&1
echo "exit=$?" >>../result
poc -output-dir lib2 -library quad2 ../Quad.Mod "other/a b.o" >>../result 2>&1
echo "exit=$?" >>../result
cd ..
rm -rf work
. ../../testresult.sh
