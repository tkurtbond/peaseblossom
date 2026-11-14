#!/bin/sh
. ../../testenv.sh
# Coroutines (doc/developer/coroutines.md, Phase 3): a generator, a copied
# record, Transfer to the running coroutine, main resumed by a coroutine
# other than the one it last resumed, a recursion on a coroutine's stack.
# Under both size models: Init's stackSize is a LONGINT.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run coroutines.mod
echo "== -OC" >>result
poc -OC -o llvm-coroutines-oc -build coroutines.mod >>result 2>&1
./llvm-coroutines-oc >>result 2>&1
printf 'exit=%d\n' "$?" >>result
rm -f *.sym llvm-coroutines-oc
. ../../testresult.sh
