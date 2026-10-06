#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 1: the size, alignment and instruction suffix
# VaxTypes.Mod gives each type, and each record field's offset
poc -dump-vax-types VaxTypesProbe.mod >result 2>&1
. ../../testresult.sh
