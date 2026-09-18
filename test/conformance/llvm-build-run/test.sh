#!/bin/sh
. ../../testenv.sh
poc -o llvm-stub-out -build stub.mod >result
./llvm-stub-out >>result
. ../../testresult.sh
