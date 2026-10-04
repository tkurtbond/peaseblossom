#!/bin/sh
. ../../testenv.sh
# Exported external procedures called from another module, under both size
# models, then the interface CLib.sym gives (PLAN.md, "Ongoing bug fixing"
# 1: the .sym lost the linkage name, and the link failed).
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  printf '== %s\n' "$model" >>result
  poc $model -o "$exe" -build client.mod >>result 2>&1
  "./$exe" >>result 2>&1
done
cat CLib.sym >>result
. ../../testresult.sh
