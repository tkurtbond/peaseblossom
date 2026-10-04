#!/bin/sh
. ../../testenv.sh
# Long strings, under both size models: a 603-character exported constant,
# through the .sym, and 1500-character literals assigned, compared, passed
# and copied (PLAN.md, "Ongoing bug fixing" 3: a string literal held at most
# 255 characters). Then the constant's length as the .sym writes it.
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  printf '== %s\n' "$model" >>result
  poc $model -o "$exe" -build client.mod >>result 2>&1
  "./$exe" >>result 2>&1
done
grep 'text\*' LongS.sym | tr -d ' ;' | awk -F'=' '{ print "LongS.sym: text*, " length($2) - 2 " characters" }' >>result
. ../../testresult.sh
