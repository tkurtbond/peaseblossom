#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): a list held only by a
# suspended stack, main's or a coroutine's, survives the collections the
# other one causes; at the default -opt, at -opt 0 and with -lto.
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
