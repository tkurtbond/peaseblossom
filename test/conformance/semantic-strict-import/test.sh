#!/bin/sh
. ../../testenv.sh
: >result
poc -emit-interface extensions.mod >>result
poc -strict -check client.mod >>result
poc -strict -emit-llvm-ir client.mod >>result
poc -strict -check extensions.mod | tail -1 >>result
. ../../testresult.sh
