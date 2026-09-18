#!/bin/sh
. ../../testenv.sh
# lib.sym is only needed so client.mod's own CheckModule can resolve
# "IMPORT Lib := lib" (ordinary .sym-based type checking, unchanged by
# step 12); the executable itself is built from lib.mod's real source,
# transitively discovered by poc_build_run's own "-build client.mod"
# below, not from this .sym file at all - see PLAN.md Phase 8 step 12's
# own header comment on ModuleInterface.ReadModuleSource*.
poc -emit-interface lib.mod >/dev/null
poc_build_run client.mod
. ../../testresult.sh
