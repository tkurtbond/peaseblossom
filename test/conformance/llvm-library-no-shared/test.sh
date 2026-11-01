#!/bin/sh
. ../../testenv.sh
# doc/developer/static-only-libraries.md: -no-shared-library goes with
# -library, before the command or after the file, and the manifest says so
# in a line of its own, which a later poc can read: a program links the
# library. Without the option there is no such line. Any other command
# refuses the option; for vax-dec-vms, fixture poc-vax-target-llvm-options.
# With it there is an archive and no shared library (OpenBSD's name is
# masked), and a rebuild deletes the shared library an earlier one left.
# A shared link that fails says the option exists; with the option that
# link is not made, so a bad -link is not found. A library with a shared
# library cannot need one without, whose code it would hold a copy of; the
# reverse is fine. An install copies only the files there are, deletes the
# shared library of a copy installed before, and a program links from it.
unset POC_IMPORT_PATH
triple=$(clang -dumpmachine)
manifest() { grep -c '^no-shared$' "$1/$triple/O2/greet.library"; }
files() {
  ls "$1/$triple/O2" | grep '^libgreet' | sed 's/\.so\.0\.0$/.so/' | LC_ALL=C sort >>../result
}
rm -rf work && mkdir work && cd work || exit 1
: >../result
echo "== before the command" >>../result
poc -output-dir before -no-shared-library -library greet ../Greet.Mod >>../result 2>&1
echo "exit=$?" >>../result
manifest before >>../result
echo "== after the file" >>../result
poc -output-dir after -library greet ../Greet.Mod -no-shared-library >>../result 2>&1
echo "exit=$?" >>../result
manifest after >>../result
echo "== without it" >>../result
poc -output-dir without -library greet ../Greet.Mod >>../result 2>&1
echo "exit=$?" >>../result
manifest without >>../result
echo "== the files" >>../result
files before
files after
files without
echo "== rebuilt without the shared library" >>../result
poc -output-dir without -no-shared-library -library greet ../Greet.Mod >>../result 2>&1
echo "exit=$?" >>../result
files without
echo "== a shared link that fails" >>../result
# only poc's own lines: the linker's differ from host to host
poc -output-dir bad -link -lnosuchlibrary -library greet ../Greet.Mod 2>&1 | grep '^poc:' >>../result
echo "== the same with the option" >>../result
poc -output-dir bad -link -lnosuchlibrary -no-shared-library -library greet ../Greet.Mod >>../result 2>&1
echo "exit=$?" >>../result
echo "== a shared library needing an archive" >>../result
poc -library-path before -output-dir needs -library uses ../Uses.Mod >>../result 2>&1
echo "exit=$?" >>../result
echo "library files: $(ls needs/$triple/O2 | grep -c -E '^libuses|^uses\.library')" >>../result
echo "== an archive needing an archive" >>../result
poc -library-path before -output-dir needs -no-shared-library -library uses ../Uses.Mod >>../result 2>&1
echo "exit=$?" >>../result
echo "== an archive needing a shared library" >>../result
poc -output-dir both -library greet ../Greet.Mod >>../result 2>&1
poc -library-path both -output-dir needs2 -no-shared-library -library uses ../Uses.Mod >>../result 2>&1
echo "exit=$?" >>../result
echo "== installed" >>../result
install() {
  poc -library-path "$1" -output-dir inst -install-library greet 2>&1 | sed "s|$triple|<triple>|" >>../result
  files inst
}
install before
echo "-- over one with a shared library" >>../result
install both
install before
poc -library-path inst -o installed -build ../main.mod >>../result 2>&1
echo "exit=$?" >>../result
./installed >>../result 2>&1
echo "== a program reads the manifest" >>../result
poc -library-path before -o main -build ../main.mod >>../result 2>&1
echo "exit=$?" >>../result
./main >>../result 2>&1
echo "== other commands" >>../result
for command in "-build ../main.mod" "-compile ../main.mod" "-check ../main.mod" "../main.mod"; do
  echo "-- $command" >>../result
  poc -library-path before -no-shared-library $command >>../result 2>&1
  echo "exit=$?" >>../result
done
cd .. || exit 1
rm -rf work
. ../../testresult.sh
