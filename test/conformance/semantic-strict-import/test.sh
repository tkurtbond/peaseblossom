#!/bin/sh
. ../../testenv.sh
: >result
poc -emit-interface extensions.mod >>result 2>&1
poc -strict -check client.mod >>result 2>&1
poc -strict -emit-llvm-ir client.mod >>result 2>&1
poc -strict -check extensions.mod 2>&1 | tail -1 >>result
. ../../testresult.sh
