#!/bin/sh
. ../../testenv.sh
# The IR of a mixed ADDRESS/LONGINT comparison, on a 32-bit target under -OC:
# the compares must be i64 (the ADDRESS sign-extended), not i32.
: >result
poc -target i686-unknown-linux-gnu -OC -emit-llvm-ir addresswidth.mod >/dev/null
grep -E 'icmp|sext|trunc' addressWidth.ll >>result
. ../../testresult.sh
