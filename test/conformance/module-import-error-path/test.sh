#!/bin/sh
. ../../testenv.sh
# A compile-time error in an imported module names the file poc read: a .Mod
# found through -import-path with its directory, one in the current directory
# as it is (it used to be the constructed Bad.mod in both cases).
: >result
poc -import-path lib -emit-llvm-ir topbad.mod >>result
poc -emit-llvm-ir toplow.mod >>result
. ../../testresult.sh
