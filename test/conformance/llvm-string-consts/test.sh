#!/bin/sh
. ../../testenv.sh
# lib.sym is only needed so client.mod's own CheckModule can resolve
# "IMPORT Lib := lib"; the executable is built from lib.mod's real
# source, transitively discovered by -build client.mod - the same
# arrangement llvm-multi-module already uses.
poc -emit-interface lib.mod >/dev/null
poc_build_run client.mod
. ../../testresult.sh
