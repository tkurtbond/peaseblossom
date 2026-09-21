#!/bin/sh
. ../../testenv.sh
# One program, one case per run (its argument), under both size models: the
# output and the exit status of each run are the expected text, except that a
# death by signal is reported as "killed by a signal" (which signal depends on
# the host).  See notrap.mod and AGENTS.md, "What traps, and what does not".
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
ulimit -c 0
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  poc $model -o "$exe" -build notrap.mod | grep -v '^semantic OK' >>result
  for case in 0 1 2 3 4 5 6 7 8 9 11 12
  do
    printf '== %s case %s\n' "$model" "$case" >>result
    # nothing here writes to stderr, so both it and the message some shells
    # print for a death by signal ("Segmentation fault", which OpenBSD's shell
    # sends to the command's own stderr and bash to its own) go to /dev/null
    { "./$exe" "$case" >out 2>/dev/null; } 2>/dev/null
    status=$?
    cat out >>result
    if [ "$status" -gt 128 ] && [ "$status" -ne 255 ]; then
      echo "killed by a signal" >>result
    else
      echo "exit=$status" >>result
    fi
  done
done
rm -f out
. ../../testresult.sh
