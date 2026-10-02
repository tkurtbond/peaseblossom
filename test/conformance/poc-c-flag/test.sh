#!/bin/sh
. ../../testenv.sh
# Phase 13 step 2: -c-flag <arg> passes <arg> to clang for a module's C part.
# part/Hash.c includes include/fnv.h, so without -c-flag -I.../include its
# compile fails, and with it the program builds - with no -o, as UseHash, the
# program module's name - and prints FNV-1a of "hello" (1335831723).
rm -rf work && mkdir work && cd work
: >../result
echo "== without -c-flag" >>../result
poc -import-path ../part ../UseHash.Mod >/dev/null 2>&1
printf 'exit=%d\n' "$?" >>../result
echo "== -c-flag -I../include" >>../result
poc -import-path ../part -c-flag -I../include ../UseHash.Mod >>../result 2>&1
printf 'exit=%d\n' "$?" >>../result
./UseHash >>../result 2>&1
echo "== -c-flag without an argument" >>../result
poc -c-flag >>../result 2>&1
printf 'exit=%d\n' "$?" >>../result
cd .. && rm -rf work
. ../../testresult.sh
