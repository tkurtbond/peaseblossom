#!/bin/sh
. ../../testenv.sh
# Tasks (doc/developer/tasks.md, Phase 9): messages held only in channels
# and on blocked tasks' stacks, and tasks only Tasks' queues point to,
# survive many collections; at the default -opt, at -opt 0 and with -lto.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run collector.mod
for option in "-opt 0" -lto
do
  echo "== $option" >>result
  poc $option -o other.exe -build collector.mod >>result 2>&1
  ./other.exe >>result 2>&1
  printf 'exit=%d\n' "$?" >>result
done
rm -f *.sym other.exe
. ../../testresult.sh
