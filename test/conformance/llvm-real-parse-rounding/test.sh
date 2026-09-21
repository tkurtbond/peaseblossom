#!/bin/sh
. ../../testenv.sh
# Each CONST's value must be the bits Python's (correctly rounded) float()
# gives its literal; see generate.py.
poc -target x86_64-unknown-linux-gnu -emit-llvm-ir realparse.mod >/dev/null
grep -o 'store double 0x[0-9A-F]*' realParse.ll >result
. ../../testresult.sh
