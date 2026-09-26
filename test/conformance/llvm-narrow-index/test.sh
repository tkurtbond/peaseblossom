#!/bin/sh
. ../../testenv.sh
poc -o llvm-narrow-index -build narrow.mod >result 2>&1
# the last statement is meant to trap: keep its message and exit status
./llvm-narrow-index >>result 2>&1
echo " exit=$?" >>result
. ../../testresult.sh
