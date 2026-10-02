#!/bin/sh
. ../../testenv.sh
# Phase 13 step 1: poc -version, and the poc version a library's manifest
# records. -version prints "poc <x.y.z>", with the commit of a build from a
# git checkout (none from a tree without .git), the target and size model in
# effect, and the first line of clang --version: here only their shape is
# compared, as the commit, the host's triple and clang's version vary. A
# library records "poc <x.y.z>", the same number; one written by another
# version, or with no "poc" line (before 0.1.0), is refused, said once, and
# the missing import's note points to it.
exe=$(basename "$PWD")
triple=$(clang -dumpmachine)
mask() { sed -e "s|$triple|<triple>|g" -e "s/$number/<number>/g"; }
: >result
echo "== -version" >>result
poc -version >version.txt 2>&1
printf 'exit=%d\n' "$?" >>result
number=$(sed -n '1s/^poc \([0-9]*\.[0-9]*\.[0-9]*\)\( ([0-9a-f]*\(-dirty\)\{0,1\})\)\{0,1\}$/\1/p' version.txt)
if [ -n "$number" ]; then echo "line 1: poc <number> [(<commit>)]" >>result; else sed -n 1p version.txt >>result; fi
sed -n 2p version.txt | mask >>result
if sed -n 3p version.txt | grep -q 'clang version'; then echo "line 3: clang version ..." >>result; else sed -n 3p version.txt >>result; fi
echo "== -OC -target i686-unknown-linux-gnu -version, line 2" >>result
poc -OC -target i686-unknown-linux-gnu -version 2>&1 | sed -n 2p >>result
echo "== -version with no clang on PATH" >>result
pocPath=$(command -v poc)
env PATH=/nonexistent "$pocPath" -version 2>&1 | sed -n '2,$p' >>result
echo "== a library records the version" >>result
rm -rf lib
poc -O2 -clear-library-path -output-dir lib -library tiny src/Tiny.Mod >/dev/null 2>&1
manifest=lib/$triple/O2/tiny.library
grep '^poc ' "$manifest" | mask >>result
poc -library-path lib -o "$exe" -build main.mod >/dev/null 2>&1 && "./$exe"
printf 'built and ran: exit=%d\n' "$?" >>result
echo "== another version's library" >>result
sed "s/^poc .*/poc 0.0.0/" "$manifest" >manifest.tmp && mv manifest.tmp "$manifest"
poc -library-path lib -o "$exe" -build main.mod 2>&1 | mask >>result
echo "== a library from before versions" >>result
grep -v '^poc ' "$manifest" >manifest.tmp && mv manifest.tmp "$manifest"
poc -library-path lib -o "$exe" -build main.mod 2>&1 | mask >>result
rm -rf lib version.txt
. ../../testresult.sh
