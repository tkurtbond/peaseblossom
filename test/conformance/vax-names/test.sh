#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 15 step 1: the symbol VaxTypes.MakeSymbol makes for each
# name, and external procedures' linkage names, verbatim
poc -dump-vax-names VaxNamesProbe.mod >result 2>&1
. ../../testresult.sh
